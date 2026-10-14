import Foundation
import Observation

/// T54 — the Bible reader tab. Ports the shape of `bible_bloc.dart`
/// (book/chapter/language navigation, `StorageService`-persisted position,
/// verse annotations) onto this codebase's own conventions: an
/// `@Observable` view model over a `BibleRepository` whose remote
/// implementation already handles the "instant on cached books" /
/// fire-and-forget background refresh behavior Dart gets from its
/// Realm-backed bloc (see `RemoteBibleRepository`'s own doc comments) —
/// this type just drives navigation intents and owns the two small local
/// stores (`ReaderPreferencesStore`/`ReaderPositionStore`).
@Observable
@MainActor
final class ReaderViewModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var state: LoadState = .loading
    private(set) var books: [BibleBook] = []
    private(set) var languages: [BibleLanguage] = []
    private(set) var currentBook: BibleBook?
    private(set) var currentLanguage: String
    private(set) var currentChapterNumber: Int
    private(set) var verses: [BibleVerse] = []
    private(set) var notesByVerseID: [String: VerseNote] = [:]
    private(set) var highlightsByVerseID: [String: VerseHighlight] = [:]
    /// A chapter navigation in flight (next/prev, book/chapter/language
    /// pick, or `refresh()`) — distinct from `state`, which only ever
    /// reflects the very first load. See `loadChapter`'s doc comment for
    /// why a mid-session failure doesn't flip `state` to `.failed`.
    private(set) var isChapterLoading = false
    private(set) var preferences: ReaderPreferences
    /// A short user-facing string set on a no-op boundary navigation (e.g.
    /// "This is the first chapter"), matching Dart's own boundary toasts in
    /// wording. The view shows it transiently, then calls
    /// `clearBoundaryMessage()`.
    private(set) var boundaryMessage: String?

    private let repository: any BibleRepository
    private let preferencesStore: ReaderPreferencesStore
    private let positionStore: ReaderPositionStore
    private let logger = AppLogger(category: .content)
    private var chapterLoadTask: Task<Void, Never>?
    /// Bumped on every dispatched chapter load; a completion only applies
    /// its result if its captured generation still matches when it
    /// finishes. Same staleness-guard shape as `SearchViewModel.generation`
    /// — rapid next/prev taps (or a stale in-flight load resuming after
    /// `chapterLoadTask?.cancel()`) must not clobber a newer chapter with
    /// an older one's result.
    private var chapterLoadGeneration = 0
    /// The persisted position's book number, carried from `init` until
    /// `loadIfNeeded()`'s `fetchInit()` call resolves it against the real
    /// `books` array (there's no `currentBook` to hold it in before then).
    private let initialBookNumber: Int

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
        let keyValueStore: any KeyValueStoring = container.resolve()
        preferencesStore = ReaderPreferencesStore(keyValueStore: keyValueStore)
        positionStore = ReaderPositionStore(keyValueStore: keyValueStore)
        preferences = preferencesStore.load()
        let position = positionStore.load()
        currentLanguage = position.languageName
        currentChapterNumber = position.chapterNumber
        initialBookNumber = position.bookNumber
    }

    var maxChapters: Int { currentBook?.chapters ?? 1 }

    // MARK: - Loading

    func loadIfNeeded() async {
        guard case .loading = state, chapterLoadTask == nil else { return }
        do {
            let result = try await repository.fetchInit()
            books = result.books
            languages = result.languages
            guard let resolvedBook = books.first(where: { $0.bookNumber == initialBookNumber }) ?? books.first else {
                // No books at all — nothing a chapter load could resolve.
                state = .failed
                return
            }
            currentBook = resolvedBook
            dispatchChapterLoad(
                bookNumber: resolvedBook.bookNumber,
                chapterNumber: currentChapterNumber,
                languageName: currentLanguage,
                isBookNumberChanged: true,
                isChapterNumberChanged: true
            )
            await chapterLoadTask?.value
        } catch {
            logger.warning("bible fetchInit failed: \(error)")
            state = .failed
        }
    }

    /// Re-runs the current chapter load. Both change flags are sent `true`
    /// so the server includes fresh notes/highlights in the response (it
    /// only does so when at least one flag is `true` — see the T54
    /// grounding summary) — a pull-to-refresh should surface fresh
    /// annotations, not just verse text. Note this is still bounded by
    /// `BibleRepository.fetchChapter`'s own cache-first contract: a cache
    /// hit returns instantly and only refreshes the cache in the
    /// background for the *next* open, matching Dart's fire-and-forget
    /// `_refreshAnnotations` precedent — that policy lives in the
    /// repository, not here.
    func refresh() async {
        guard let currentBook else { return }
        dispatchChapterLoad(
            bookNumber: currentBook.bookNumber,
            chapterNumber: currentChapterNumber,
            languageName: currentLanguage,
            isBookNumberChanged: true,
            isChapterNumberChanged: true
        )
        await chapterLoadTask?.value
    }

    // MARK: - Navigation

    func goToNextChapter() {
        guard let currentBook else { return }
        guard currentChapterNumber < maxChapters else {
            boundaryMessage = "This is the last chapter"
            return
        }
        dispatchChapterLoad(
            bookNumber: currentBook.bookNumber,
            chapterNumber: currentChapterNumber + 1,
            languageName: currentLanguage,
            isBookNumberChanged: false,
            isChapterNumberChanged: true
        )
    }

    func goToPreviousChapter() {
        guard let currentBook else { return }
        guard currentChapterNumber > 1 else {
            boundaryMessage = "This is the first chapter"
            return
        }
        dispatchChapterLoad(
            bookNumber: currentBook.bookNumber,
            chapterNumber: currentChapterNumber - 1,
            languageName: currentLanguage,
            isBookNumberChanged: false,
            isChapterNumberChanged: true
        )
    }

    func goToNextBook() {
        guard let currentBook else { return }
        guard let nextBook = books.first(where: { $0.bookNumber == currentBook.bookNumber + 1 }) else {
            boundaryMessage = "This is the last book"
            return
        }
        dispatchChapterLoad(
            bookNumber: nextBook.bookNumber,
            chapterNumber: 1,
            languageName: currentLanguage,
            isBookNumberChanged: true,
            isChapterNumberChanged: true
        )
    }

    func goToPreviousBook() {
        guard let currentBook else { return }
        guard let previousBook = books.first(where: { $0.bookNumber == currentBook.bookNumber - 1 }) else {
            boundaryMessage = "This is the first book"
            return
        }
        dispatchChapterLoad(
            bookNumber: previousBook.bookNumber,
            chapterNumber: 1,
            languageName: currentLanguage,
            isBookNumberChanged: true,
            isChapterNumberChanged: true
        )
    }

    func select(book: BibleBook) {
        dispatchChapterLoad(
            bookNumber: book.bookNumber,
            chapterNumber: 1,
            languageName: currentLanguage,
            isBookNumberChanged: true,
            isChapterNumberChanged: true
        )
    }

    func select(chapterNumber: Int) {
        guard let currentBook else { return }
        // Defensive clamp — `ChapterGridSheet` only ever offers
        // `1...book.chapters`, but this keeps a stray out-of-range call
        // from requesting a chapter the current book doesn't have.
        let clamped = min(max(chapterNumber, 1), currentBook.chapters)
        dispatchChapterLoad(
            bookNumber: currentBook.bookNumber,
            chapterNumber: clamped,
            languageName: currentLanguage,
            isBookNumberChanged: false,
            isChapterNumberChanged: true
        )
    }

    /// T56 — a single-shot jump to an arbitrary book/chapter, for
    /// `ReaderNavigationStore`'s pending-target consumption (a verse-of-day
    /// tap/push/deep link). Unlike `select(book:)` + `select(chapterNumber:)`
    /// chained together, this dispatches exactly one load: the latter
    /// requires `currentBook` to already equal the target book (it clamps
    /// against `currentBook.chapters`), which isn't true yet right after
    /// `select(book:)` resets to chapter 1 — chaining them would need an
    /// awaited round trip between the two and would fire two separate
    /// network loads instead of one.
    func select(bookNumber: Int, chapterNumber: Int) {
        guard let book = books.first(where: { $0.bookNumber == bookNumber }) else { return }
        let clamped = min(max(chapterNumber, 1), book.chapters)
        dispatchChapterLoad(
            bookNumber: book.bookNumber,
            chapterNumber: clamped,
            languageName: currentLanguage,
            isBookNumberChanged: true,
            isChapterNumberChanged: true
        )
    }

    /// A language switch is a content change, matching Dart's own
    /// `ReadOnContentChangedEvent(language:)` dispatch — so this sends
    /// `isChapterNumberChanged: true`, not a no-op flag pair, even though
    /// neither the book nor the chapter number actually moved.
    func select(language: String) {
        guard let currentBook else { return }
        dispatchChapterLoad(
            bookNumber: currentBook.bookNumber,
            chapterNumber: currentChapterNumber,
            languageName: language,
            isBookNumberChanged: false,
            isChapterNumberChanged: true
        )
    }

    func clearBoundaryMessage() {
        boundaryMessage = nil
    }

    // MARK: - Annotations

    func toggleHighlight(verseID: String, colorHex: String) async {
        do {
            let highlight = try await repository.syncHighlight(verseId: verseID, colorHex: colorHex)
            if let highlight {
                highlightsByVerseID[verseID] = highlight
            } else {
                highlightsByVerseID.removeValue(forKey: verseID)
            }
        } catch {
            logger.warning("toggle highlight for verse \(verseID) failed: \(error)")
        }
    }

    func removeHighlight(verseID: String) async {
        do {
            _ = try await repository.syncHighlight(verseId: verseID, colorHex: nil)
            highlightsByVerseID.removeValue(forKey: verseID)
        } catch {
            logger.warning("remove highlight for verse \(verseID) failed: \(error)")
        }
    }

    func saveNote(verseID: String, content: String) async {
        do {
            let note = try await repository.syncNote(verseId: verseID, content: content)
            if let note {
                notesByVerseID[verseID] = note
            } else {
                notesByVerseID.removeValue(forKey: verseID)
            }
        } catch {
            logger.warning("save note for verse \(verseID) failed: \(error)")
        }
    }

    func deleteNote(verseID: String) async {
        do {
            _ = try await repository.syncNote(verseId: verseID, content: nil)
            notesByVerseID.removeValue(forKey: verseID)
        } catch {
            logger.warning("delete note for verse \(verseID) failed: \(error)")
        }
    }

    func shareURL(for verse: BibleVerse) async -> URL? {
        try? await repository.shareVerse(id: verse.id)
    }

    // MARK: - Preferences

    func setFontSize(_ size: Double) {
        let range = ReaderPreferences.fontSizeRange
        preferences.fontSize = min(max(size, range.lowerBound), range.upperBound)
        preferencesStore.save(preferences)
    }

    func setTheme(_ theme: ReaderTheme) {
        preferences.theme = theme
        preferencesStore.save(preferences)
    }

    // MARK: - Chapter loading (private)

    /// Cancels any in-flight chapter load, bumps the staleness generation,
    /// and kicks a fresh one — the synchronous entry point every
    /// navigation intent above goes through. `loadIfNeeded()`/`refresh()`
    /// additionally `await chapterLoadTask?.value` right after, since
    /// those two callers are themselves `async` and need to hand their
    /// caller a finished load; every other navigation intent is
    /// intentionally fire-and-forget, observed through `isChapterLoading`/
    /// `state` rather than awaited.
    private func dispatchChapterLoad(
        bookNumber: Int,
        chapterNumber: Int,
        languageName: String,
        isBookNumberChanged: Bool,
        isChapterNumberChanged: Bool
    ) {
        chapterLoadTask?.cancel()
        chapterLoadGeneration += 1
        let generation = chapterLoadGeneration
        isChapterLoading = true
        chapterLoadTask = Task {
            await loadChapter(
                bookNumber: bookNumber,
                chapterNumber: chapterNumber,
                languageName: languageName,
                isBookNumberChanged: isBookNumberChanged,
                isChapterNumberChanged: isChapterNumberChanged,
                generation: generation
            )
        }
    }

    /// On failure, `state` only flips to `.failed` while it's still
    /// `.loading` — i.e. only for the very first chapter this view model
    /// ever loads. A mid-session navigation failure (state already
    /// `.loaded`) instead just logs and leaves whatever chapter is already
    /// on screen, matching `UserPlaylistDetailViewModel.loadMore()`'s
    /// "leave what's on screen, let the user's own retry try again"
    /// precedent, rather than yanking a working reader to a full-screen
    /// error over one flaky navigation.
    private func loadChapter(
        bookNumber: Int,
        chapterNumber: Int,
        languageName: String,
        isBookNumberChanged: Bool,
        isChapterNumberChanged: Bool,
        generation: Int
    ) async {
        defer {
            if generation == chapterLoadGeneration {
                isChapterLoading = false
            }
        }
        do {
            let chapter = try await repository.fetchChapter(
                bookNumber: bookNumber,
                chapterNumber: chapterNumber,
                languageName: languageName,
                isBookNumberChanged: isBookNumberChanged,
                isChapterNumberChanged: isChapterNumberChanged
            )
            guard generation == chapterLoadGeneration else { return }
            apply(chapter: chapter)
            state = .loaded
        } catch {
            guard generation == chapterLoadGeneration else { return }
            logger.warning("load chapter \(bookNumber)/\(chapterNumber) lang \(languageName) failed: \(error)")
            if case .loading = state {
                state = .failed
            }
        }
        if generation == chapterLoadGeneration {
            chapterLoadTask = nil
        }
    }

    /// Dictionaries keyed by `VerseHighlight.verseId`/`VerseNote.verseId`
    /// (a later duplicate wins over an earlier one, defensively — the
    /// backend never sends two rows for the same verse in practice).
    /// Persists `ReaderPosition` here, once per successful load, rather
    /// than from a property observer on `currentBook`/`currentLanguage`/
    /// `currentChapterNumber` individually — this is the one place all
    /// three actually change together as a result of navigation.
    private func apply(chapter: BibleChapter) {
        verses = chapter.verses
        notesByVerseID = Dictionary(
            chapter.notes.map { ($0.verseId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        highlightsByVerseID = Dictionary(
            chapter.highlights.map { ($0.verseId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        currentChapterNumber = chapter.chapterNumber
        currentLanguage = chapter.languageName
        currentBook = books.first(where: { $0.bookNumber == chapter.bookNumber }) ?? currentBook
        positionStore.save(ReaderPosition(
            bookNumber: chapter.bookNumber,
            chapterNumber: chapter.chapterNumber,
            languageName: chapter.languageName
        ))
    }
}
