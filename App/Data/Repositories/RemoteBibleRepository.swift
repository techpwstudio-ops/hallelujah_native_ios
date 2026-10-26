import Foundation

/// T54 (Bible reader) — `src/routes/user/book.routes.js` +
/// `book.controller.js`. See `BibleRepository`'s doc comments for the
/// per-method contract this mirrors.
final class RemoteBibleRepository: BibleRepository {
    private let client: HTTPClient
    private let cache: BibleChapterCaching
    private let pending: PendingBibleAnnotationStore
    private let logger = AppLogger(category: .content)

    init(client: HTTPClient, database: Database) {
        self.client = client
        cache = BibleChapterCache(database: database)
        pending = PendingBibleAnnotationStore(database: database)
    }

    func fetchInit() async throws -> BibleInitResult {
        let response = try await client.send(.bibleInit)
        guard response.statusCode == 200 else {
            throw BibleRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(BibleInitResponseDTO.self, from: response.data)
        return BibleInitResult(
            books: decoded.books.compactMap { $0.toDomain() },
            languages: decoded.bookLanguages.map { $0.toDomain() }
        )
    }

    /// Mirrors Dart's "instant on cached books": a cache hit returns the
    /// full cached chapter immediately, then kicks a detached background
    /// refresh that re-fetches from network and updates the cache for the
    /// next open — fire-and-forget, errors swallowed, matching Dart's own
    /// `_refreshAnnotations`. Scope cut: unlike Dart's Realm-backed reactive
    /// bloc, this background refresh does not push a live update into an
    /// already-open reader screen (no cross-cutting reactive store exists
    /// for this one feature to justify building) — it only makes the next
    /// open of that chapter fresh.
    func fetchChapter(
        bookNumber: Int,
        chapterNumber: Int,
        languageName: String,
        isBookNumberChanged: Bool,
        isChapterNumberChanged: Bool
    ) async throws -> BibleChapter {
        if let cached = await cache.chapter(languageName: languageName, bookNumber: bookNumber, chapterNumber: chapterNumber) {
            Task.detached {
                do {
                    let fresh = try await self.fetchChapterFromNetwork(
                        bookNumber: bookNumber,
                        chapterNumber: chapterNumber,
                        languageName: languageName,
                        isBookNumberChanged: isBookNumberChanged,
                        isChapterNumberChanged: isChapterNumberChanged
                    )
                    await self.cache.store(await self.applyingPending(to: fresh))
                } catch {
                    self.logger.warning("Background chapter refresh failed: \(error)")
                }
            }
            return await applyingPending(to: cached)
        }

        let fresh = try await fetchChapterFromNetwork(
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            languageName: languageName,
            isBookNumberChanged: isBookNumberChanged,
            isChapterNumberChanged: isChapterNumberChanged
        )
        let merged = await applyingPending(to: fresh)
        await cache.store(merged)
        return merged
    }

    /// Offline (or when the request can't reach the server) the edit is
    /// kept: written into the cached chapter and queued, and sent by
    /// `flushPendingAnnotations` once the connection is back. The last edit
    /// of a verse wins, as each sync sends the verse's complete state.
    func syncHighlight(
        verseId: String,
        words: [VerseHighlight.Word],
        location: BibleVerseLocation
    ) async throws -> VerseHighlight? {
        let local = words.isEmpty ? nil : VerseHighlight(id: verseId, verseId: verseId, words: words)
        if await Self.isOffline() {
            await queueHighlight(local, words: words, verseId: verseId, location: location)
            return local
        }
        do {
            let saved = try await sendHighlight(verseId: verseId, words: words)
            await pending.remove(kind: .highlight, verseID: verseId)
            await cache.patchHighlight(words.isEmpty ? nil : (saved ?? local), verseID: verseId, location: location)
            return saved
        } catch let error where Self.isConnectivityFailure(error) {
            await queueHighlight(local, words: words, verseId: verseId, location: location)
            return local
        }
    }

    func syncNote(verseId: String, content: String?, location: BibleVerseLocation) async throws -> VerseNote? {
        let text = content ?? ""
        if await Self.isOffline() {
            return await queueNote(text, verseId: verseId, location: location)
        }
        do {
            let note = try await sendNote(verseId: verseId, content: content)
            await pending.remove(kind: .note, verseID: verseId)
            await cache.patchNote(note, verseID: verseId, location: location)
            return note
        } catch let error where Self.isConnectivityFailure(error) {
            return await queueNote(text, verseId: verseId, location: location)
        }
    }

    /// Sends every queued offline edit, oldest first. Stops at the first
    /// connection failure (the rest wait for the next attempt); an edit the
    /// server rejects outright (4xx) is dropped so it can't block the queue.
    func flushPendingAnnotations() async {
        guard await BibleAnnotationFlushGate.shared.begin() else { return }
        defer { Task { await BibleAnnotationFlushGate.shared.end() } }

        for item in await pending.all() {
            do {
                switch item.kind {
                case .highlight:
                    let words = item.highlightWords
                    let saved = try await sendHighlight(verseId: item.verseID, words: words)
                    let applied = words.isEmpty
                        ? nil
                        : (saved ?? VerseHighlight(id: item.verseID, verseId: item.verseID, words: words))
                    await pending.remove(kind: .highlight, verseID: item.verseID, ifUnchangedSince: item.updatedAt)
                    await cache.patchHighlight(applied, verseID: item.verseID, location: item.location)
                case .note:
                    let content = item.noteContent
                    let note = try await sendNote(verseId: item.verseID, content: content.isEmpty ? nil : content)
                    await pending.remove(kind: .note, verseID: item.verseID, ifUnchangedSince: item.updatedAt)
                    await cache.patchNote(note, verseID: item.verseID, location: item.location)
                }
            } catch let error where Self.isConnectivityFailure(error) {
                logger.info("pending bible annotations: still offline, \(item.kind.rawValue) \(item.verseID) waits")
                return
            } catch BibleRepositoryError.unexpectedStatus(let code) where (400..<500).contains(code) && code != 401 && code != 408 && code != 429 {
                logger.warning("pending \(item.kind.rawValue) for verse \(item.verseID) rejected (\(code)), dropped")
                await pending.remove(kind: item.kind, verseID: item.verseID, ifUnchangedSince: item.updatedAt)
            } catch {
                logger.warning("pending \(item.kind.rawValue) for verse \(item.verseID) failed: \(error)")
                return
            }
        }
    }

    func clearPendingAnnotations() async {
        await pending.removeAll()
    }

    // MARK: - Offline queue

    private func queueHighlight(
        _ local: VerseHighlight?,
        words: [VerseHighlight.Word],
        verseId: String,
        location: BibleVerseLocation
    ) async {
        let payload = (try? JSONEncoder().encode(words)) ?? Data("[]".utf8)
        await pending.enqueue(kind: .highlight, verseID: verseId, location: location, payload: payload)
        await cache.patchHighlight(local, verseID: verseId, location: location)
    }

    private func queueNote(_ text: String, verseId: String, location: BibleVerseLocation) async -> VerseNote? {
        await pending.enqueue(kind: .note, verseID: verseId, location: location, payload: Data(text.utf8))
        guard !text.isEmpty else {
            await cache.deleteLocalNote(verseID: verseId)
            await cache.patchNote(nil, verseID: verseId, location: location)
            return nil
        }
        let note = VerseNote(
            id: verseId,
            verseId: verseId,
            content: text,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        await cache.upsertLocalNote(
            note,
            bookNumber: location.bookNumber,
            chapterNumber: location.chapterNumber,
            verseNumber: location.verseNumber
        )
        await cache.patchNote(note, verseID: verseId, location: location)
        return note
    }

    /// Queued edits for `chapter`'s verses, laid over what the server or the
    /// cache returned, so a refresh never shows an unsent edit as undone.
    private func applyingPending(to chapter: BibleChapter) async -> BibleChapter {
        let queued = await pending.pending(bookNumber: chapter.bookNumber, chapterNumber: chapter.chapterNumber)
        let verseIDs = Set(chapter.verses.map(\.id))
        let mine = queued.filter { verseIDs.contains($0.verseID) }
        guard !mine.isEmpty else { return chapter }

        var highlights = chapter.highlights
        var notes = chapter.notes
        for item in mine {
            switch item.kind {
            case .highlight:
                highlights.removeAll { $0.verseId == item.verseID }
                let words = item.highlightWords
                if !words.isEmpty {
                    highlights.append(VerseHighlight(id: item.verseID, verseId: item.verseID, words: words))
                }
            case .note:
                notes.removeAll { $0.verseId == item.verseID }
                let content = item.noteContent
                if !content.isEmpty {
                    notes.append(VerseNote(id: item.verseID, verseId: item.verseID, content: content))
                }
            }
        }
        return BibleChapter(
            bookNumber: chapter.bookNumber,
            chapterNumber: chapter.chapterNumber,
            languageName: chapter.languageName,
            verses: chapter.verses,
            notes: notes,
            highlights: highlights
        )
    }

    @MainActor
    private static func isOffline() -> Bool {
        !ReachabilityBroadcast.shared.isOnline
    }

    private static func isConnectivityFailure(_ error: Error) -> Bool {
        let urlError: URLError
        if let apiError = error as? APIError, case .transport(let wrapped) = apiError {
            urlError = wrapped
        } else if let direct = error as? URLError {
            urlError = direct
        } else {
            return false
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    // MARK: - Requests

    private func sendHighlight(verseId: String, words: [VerseHighlight.Word]) async throws -> VerseHighlight? {
        // An empty list removes the highlight (`highlights: []`); otherwise
        // one `{index, color}` entry per highlighted word.
        let highlights = words.map { HighlightColorEntryDTO(color: $0.colorHex, index: $0.index) }
        let body = try JSONEncoder().encode(SyncHighlightRequestDTO(verseId: verseId, highlights: highlights))
        let response = try await client.send(.bibleHighlightSync, body: body)
        guard response.statusCode == 200 else {
            throw BibleRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(SyncHighlightResponseDTO.self, from: response.data)
        return decoded.data?.toDomain()
    }

    private func sendNote(verseId: String, content: String?) async throws -> VerseNote? {
        let body = try JSONEncoder().encode(SyncNoteRequestDTO(verseId: verseId, content: content))
        let response = try await client.send(.bibleNoteSync, body: body)
        guard response.statusCode == 200 else {
            throw BibleRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(SyncNoteResponseDTO.self, from: response.data)
        guard let noteDTO = decoded.data else {
            // `content` nil/empty deletes the note server-side (`data: null`).
            await cache.deleteLocalNote(verseID: verseId)
            return nil
        }
        let note = noteDTO.toDomain()
        await cache.upsertLocalNote(
            note,
            bookNumber: noteDTO.bookNumber,
            chapterNumber: noteDTO.chapterNumber,
            verseNumber: noteDTO.verseNumber
        )
        return note
    }

    func shareVerse(id: String) async throws -> URL {
        let response = try await client.send(.bibleVerseShare(id: id))
        guard response.statusCode == 200 else {
            throw BibleRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(ShareVerseResponseDTO.self, from: response.data)
        guard let url = URL(string: decoded.data.link) else {
            throw BibleRepositoryError.invalidShareURL
        }
        return url
    }

    func fetchLocalNotes() async -> [BibleNoteEntry] {
        await cache.allLocalNotes()
    }

    /// The shared network round trip both the cache-hit (background) and
    /// cache-miss (synchronous) paths of `fetchChapter` call. Also updates
    /// the local notes ledger for each non-empty note the response carries,
    /// mirroring Dart writing both `BookChapter` and `ReadService.setNotes`
    /// from the one response.
    private func fetchChapterFromNetwork(
        bookNumber: Int,
        chapterNumber: Int,
        languageName: String,
        isBookNumberChanged: Bool,
        isChapterNumberChanged: Bool
    ) async throws -> BibleChapter {
        let response = try await client.send(
            .bibleChapterVerses(
                bookNumber: bookNumber,
                chapterNumber: chapterNumber,
                languageName: languageName,
                isBookNumberChanged: isBookNumberChanged,
                isChapterNumberChanged: isChapterNumberChanged
            )
        )
        guard response.statusCode == 200 else {
            throw BibleRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(BibleChapterResponseDTO.self, from: response.data)
        // Flutter keys the chapter by what it asked for, not by the numbers
        // the server echoes back; so does this. A mismatch is only logged.
        let resolvedBook = bookNumber
        let resolvedChapter = chapterNumber
        let resolvedLanguage = decoded.languageName ?? languageName
        if let echoedBook = decoded.bookNumber, let echoedChapter = decoded.chapterNumber,
           echoedBook != bookNumber || echoedChapter != chapterNumber {
            logger.warning("chapter response for \(bookNumber)/\(chapterNumber) echoed \(echoedBook)/\(echoedChapter)")
        }

        let verses = decoded.verses.map { $0.toDomain(bookNumber: resolvedBook, fallbackChapter: resolvedChapter) }
        let noteDTOs = decoded.notes ?? []
        let notes = noteDTOs.map { $0.toDomain() }
        let highlights = (decoded.highlights ?? []).compactMap { $0.toDomain() }

        for noteDTO in noteDTOs where !noteDTO.content.isEmpty {
            await cache.upsertLocalNote(
                noteDTO.toDomain(),
                bookNumber: noteDTO.bookNumber,
                chapterNumber: noteDTO.chapterNumber,
                verseNumber: noteDTO.verseNumber
            )
        }

        return BibleChapter(
            bookNumber: resolvedBook,
            chapterNumber: resolvedChapter,
            languageName: resolvedLanguage,
            verses: verses,
            notes: notes,
            highlights: highlights
        )
    }
}

/// One flush at a time across every `RemoteBibleRepository` instance (the
/// container builds a new one per resolve), so a reconnect and the reader
/// opening at once can't send the same queued edit twice.
actor BibleAnnotationFlushGate {
    static let shared = BibleAnnotationFlushGate()
    private var running = false

    func begin() -> Bool {
        guard !running else { return false }
        running = true
        return true
    }

    func end() {
        running = false
    }
}
