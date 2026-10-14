import Foundation
import Observation

/// T55 — orchestrates whole-language offline Bible downloads, mirroring
/// `bible_offline_service.dart`'s `BibleOfflineService`. Deliberate scope
/// cuts from the Dart original, all safe given this is a from-scratch
/// device with no pre-existing offline data to migrate:
/// - No 24h revalidation sweep or per-book version-stamp conditional
///   re-fetch (`_isRevalidationDue`/`_storedVersion`) — a language, once
///   downloaded, is trusted until explicitly removed and re-downloaded.
/// - No "skip books already cached from ordinary reading" pre-check
///   (`_isBookCached`) — every `downloadLanguage` run fetches every book.
/// - No notification-tray progress/result posting — there is no native
///   equivalent wired for local download-progress notifications yet;
///   `status` is the only progress surface, for in-app UI to observe.
@MainActor
@Observable
final class BibleOfflineDownloadService {
    /// Same rationale as Dart's own `_concurrency = 2`: caps simultaneous
    /// CDN connections, not a server request budget.
    private static let concurrency = 2
    private static let downloadedLanguagesKey = "bible_offline_downloaded_languages"

    private(set) var status: BibleOfflineStatus = .idle

    private let bibleRepository: any BibleRepository
    private let offlineRepository: any BibleOfflineRepository
    private let chapterCache: any BibleChapterCaching
    private let keyValueStore: any KeyValueStoring
    private let logger = AppLogger(category: .content)

    /// One in-flight run per language — a second caller joins the same
    /// `Task` rather than starting a duplicate download, mirroring Dart's
    /// `_active` map join. Swift's `Task.value` supports multiple awaiters
    /// natively, so unlike Dart there is no need for a manual continuation
    /// list here.
    private var activeTasks: [String: Task<Bool, Never>] = [:]
    private var activeProgress: [String: BibleOfflineProgress] = [:]
    private var downloadedLanguages: Set<String>

    /// Mirrors `_snapshotTriggerResult`/`_snapshotTriggerInFlight`: one
    /// trigger-and-poll cycle per language per download run, shared by every
    /// book worker that hits a missing snapshot for that language.
    private var snapshotTriggerResult: [String: Bool] = [:]
    private var snapshotTriggerTasks: [String: Task<Bool, Never>] = [:]

    init(
        bibleRepository: any BibleRepository,
        offlineRepository: any BibleOfflineRepository,
        chapterCache: any BibleChapterCaching,
        keyValueStore: any KeyValueStoring
    ) {
        self.bibleRepository = bibleRepository
        self.offlineRepository = offlineRepository
        self.chapterCache = chapterCache
        self.keyValueStore = keyValueStore
        if let data = keyValueStore.data(forKey: Self.downloadedLanguagesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            downloadedLanguages = decoded
        } else {
            downloadedLanguages = []
        }
    }

    func isLanguageDownloaded(_ language: String) -> Bool {
        downloadedLanguages.contains(language)
    }

    func isDownloading(_ language: String) -> Bool {
        activeTasks[language] != nil
    }

    /// Starts (or joins) downloading `language`'s whole Bible for offline
    /// reading. Safe to call repeatedly — a language already saved returns
    /// `true` immediately, one already downloading is joined.
    @discardableResult
    func downloadLanguage(_ language: String) async -> Bool {
        if isLanguageDownloaded(language) { return true }
        if let existing = activeTasks[language] {
            return await existing.value
        }

        snapshotTriggerResult[language] = nil
        activeProgress[language] = BibleOfflineProgress(language: language, completed: 0, total: 0)
        emitStatus()

        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.runDownload(language: language)
        }
        activeTasks[language] = task

        let result = await task.value

        activeTasks[language] = nil
        activeProgress[language] = nil
        snapshotTriggerResult[language] = nil
        emitStatus()
        if result {
            downloadedLanguages.insert(language)
            persistDownloadedLanguages()
        }
        return result
    }

    /// Removes `language`'s cached chapters and downloaded flag. Refuses (returns
    /// `false`) while a download for it is in flight — matches Dart's
    /// `deleteLanguage`: free the slot by letting the download finish or fail
    /// first, don't delete out from under it.
    @discardableResult
    func deleteLanguage(_ language: String) async -> Bool {
        guard !isDownloading(language) else { return false }
        await chapterCache.deleteChapters(languageName: language)
        downloadedLanguages.remove(language)
        persistDownloadedLanguages()
        return true
    }

    private func runDownload(language: String) async -> Bool {
        let initResult: BibleInitResult
        do {
            initResult = try await bibleRepository.fetchInit()
        } catch {
            logger.warning("Offline download for \(language) aborted: fetchInit failed: \(error)")
            return false
        }
        let books = initResult.books.filter { $0.chapters > 0 }
        guard !books.isEmpty else {
            logger.warning("Offline download for \(language) aborted: no books in fetchInit result")
            return false
        }

        activeProgress[language] = BibleOfflineProgress(language: language, completed: 0, total: books.count)
        emitStatus()

        var failures = 0
        var completed = 0
        var index = 0
        while index < books.count {
            let chunk = Array(books[index..<min(index + Self.concurrency, books.count)])
            await withTaskGroup(of: Bool.self) { group in
                for book in chunk {
                    group.addTask { [self] in
                        await self.downloadBook(language: language, book: book)
                    }
                }
                for await succeeded in group {
                    if !succeeded { failures += 1 }
                    completed += 1
                    activeProgress[language] = BibleOfflineProgress(language: language, completed: completed, total: books.count)
                    emitStatus()
                }
            }
            index += Self.concurrency
        }

        // A couple of missing books (server-side data gaps) shouldn't block
        // offline mode entirely — same 10% threshold as Dart's own
        // `failures < books.length * 0.1`.
        let success = Double(failures) < Double(books.count) * 0.1
        if !success {
            logger.warning("Offline download for \(language) failed: \(failures) of \(books.count) books could not be fetched")
        }
        return success
    }

    /// One book: fetch its snapshot, cache every chapter it has. A 404/403
    /// triggers regeneration once per language (`triggerAndAwaitSnapshot`)
    /// and retries; any other failure is reported to the caller for the
    /// 10%-threshold tally.
    private func downloadBook(language: String, book: BibleBook) async -> Bool {
        do {
            let chapters = try await offlineRepository.fetchBookSnapshot(language: language, bookNumber: book.bookNumber)
            await cache(chapters)
            return true
        } catch BibleOfflineRepositoryError.notFound {
            let ready = await triggerAndAwaitSnapshot(language: language, bookNumber: book.bookNumber)
            guard ready else {
                logger.warning("\(language) book \(book.bookNumber): still missing after trigger")
                return false
            }
            do {
                let chapters = try await offlineRepository.fetchBookSnapshot(language: language, bookNumber: book.bookNumber)
                await cache(chapters)
                return true
            } catch {
                logger.warning("\(language) book \(book.bookNumber): retry after trigger failed: \(error)")
                return false
            }
        } catch {
            logger.warning("\(language) book \(book.bookNumber): fetch failed: \(error)")
            return false
        }
    }

    /// Empty is a partially-translated book (server answered, no verses for
    /// this language) — nothing to cache, not a failure. See
    /// `BibleOfflineRepository.fetchBookSnapshot`'s doc comment.
    private func cache(_ chapters: [BibleChapter]) async {
        for chapter in chapters {
            await chapterCache.store(chapter)
        }
    }

    private func triggerAndAwaitSnapshot(language: String, bookNumber: Int) async -> Bool {
        if let cached = snapshotTriggerResult[language] { return cached }
        if let existing = snapshotTriggerTasks[language] {
            return await existing.value
        }

        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.runSnapshotTrigger(language: language, bookNumber: bookNumber)
        }
        snapshotTriggerTasks[language] = task
        let result = await task.value
        snapshotTriggerTasks[language] = nil
        snapshotTriggerResult[language] = result
        return result
    }

    /// Bounded to 6 tries, 5s apart, same as Dart — a stuck backend job
    /// can't hang a download forever; a book that never lands just counts
    /// toward the 10% failure threshold.
    private func runSnapshotTrigger(language: String, bookNumber: Int) async -> Bool {
        let accepted = (try? await offlineRepository.triggerSnapshotRegeneration(language: language)) ?? false
        guard accepted else { return false }

        let attempts = 6
        for _ in 0..<attempts {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if (try? await offlineRepository.fetchBookSnapshot(language: language, bookNumber: bookNumber)) != nil {
                return true
            }
        }
        logger.warning("\(language): snapshot never landed after \(attempts) polls")
        return false
    }

    private func emitStatus() {
        status = BibleOfflineStatus(active: Array(activeProgress.values))
    }

    private func persistDownloadedLanguages() {
        guard let data = try? JSONEncoder().encode(downloadedLanguages) else { return }
        keyValueStore.setData(data, forKey: Self.downloadedLanguagesKey)
    }
}
