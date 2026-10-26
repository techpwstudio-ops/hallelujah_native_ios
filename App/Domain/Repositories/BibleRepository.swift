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

    /// Sends the verse's complete word highlights
    /// (`highlights: [{index, color}]`); an empty list removes the highlight.
    /// Returns the server's row, `nil` once nothing is highlighted. Without
    /// a connection the edit is saved on the device and queued instead (see
    /// `flushPendingAnnotations`), and the local row is returned.
    func syncHighlight(
        verseId: String,
        words: [VerseHighlight.Word],
        location: BibleVerseLocation
    ) async throws -> VerseHighlight?

    /// `content` nil or empty deletes the note server-side. Offline, queued
    /// like `syncHighlight`.
    func syncNote(verseId: String, content: String?, location: BibleVerseLocation) async throws -> VerseNote?

    /// Sends highlights and notes saved while offline. Safe to call any
    /// time; does nothing when the queue is empty or still offline.
    func flushPendingAnnotations() async

    /// Sign-out: unsent edits belong to the account that made them.
    func clearPendingAnnotations() async

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
