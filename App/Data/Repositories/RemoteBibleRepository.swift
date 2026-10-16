import Foundation

/// T54 (Bible reader) — `src/routes/user/book.routes.js` +
/// `book.controller.js`. See `BibleRepository`'s doc comments for the
/// per-method contract this mirrors.
final class RemoteBibleRepository: BibleRepository {
    private let client: HTTPClient
    private let cache: BibleChapterCaching
    private let logger = AppLogger(category: .content)

    init(client: HTTPClient, database: Database) {
        self.client = client
        cache = BibleChapterCache(database: database)
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
                    await self.cache.store(fresh)
                } catch {
                    self.logger.warning("Background chapter refresh failed: \(error)")
                }
            }
            return cached
        }

        let fresh = try await fetchChapterFromNetwork(
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            languageName: languageName,
            isBookNumberChanged: isBookNumberChanged,
            isChapterNumberChanged: isChapterNumberChanged
        )
        await cache.store(fresh)
        return fresh
    }

    func syncHighlight(verseId: String, words: [VerseHighlight.Word]) async throws -> VerseHighlight? {
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

    func syncNote(verseId: String, content: String?) async throws -> VerseNote? {
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

        let verses = decoded.verses.map { $0.toDomain(bookNumber: decoded.bookNumber) }
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
            bookNumber: decoded.bookNumber,
            chapterNumber: decoded.chapterNumber,
            languageName: decoded.languageName,
            verses: verses,
            notes: notes,
            highlights: highlights
        )
    }
}
