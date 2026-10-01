import Foundation

/// `GET /book/init`'s two top-level collections, mapped together
/// (`book.controller.js`).
struct BibleInitResult: Sendable, Equatable {
    let books: [BibleBook]
    let languages: [BibleLanguage]
}

/// T54 (Bible reader), grounded in `src/routes/user/book.routes.js`.
/// Deliberately does NOT include the CDN whole-language snapshot download,
/// the bulk `GET /book/verses` endpoint, or `GET /book/search` — those are
/// T55's scope (offline bible and search), a separate repository.
protocol BibleRepository: Sendable {
    func fetchInit() async throws -> BibleInitResult

    /// `GET /book/chapter/verses`. `isBookNumberChanged`/`isChapterNumberChanged`
    /// are sent as the string `"true"`/`"false"` — the server only includes
    /// `notes`/`highlights` in the response when at least one is exactly
    /// `"true"`. This call also records a "read" analytics event
    /// server-side; callers must invoke it exactly once per genuine chapter
    /// navigation, never speculatively.
    func fetchChapter(
        bookNumber: Int,
        chapterNumber: Int,
        languageName: String,
        isBookNumberChanged: Bool,
        isChapterNumberChanged: Bool
    ) async throws -> BibleChapter

    /// `colorHex` `nil` removes the highlight (sends `highlights: []`);
    /// non-nil sets it (sends `highlights: [{color: colorHex}]`).
    /// Whole-verse granularity only (T54's scope cut) — never touches word
    /// indices.
    func syncHighlight(verseId: String, colorHex: String?) async throws -> VerseHighlight?

    /// `content` nil or empty deletes the note server-side.
    func syncNote(verseId: String, content: String?) async throws -> VerseNote?

    func shareVerse(id: String) async throws -> URL

    /// Local-only, no network I/O. Backed by the on-device note ledger
    /// (`CachedVerseNote`) accumulated as chapters are read / notes are
    /// saved — mirrors Dart's Realm-backed `showBookNotes`, since the
    /// backend has no bulk notes-listing endpoint (confirmed absent by
    /// grep). Returned newest-first.
    func fetchLocalNotes() async -> [BibleNoteEntry]
}

enum BibleRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
    case invalidShareURL
}
