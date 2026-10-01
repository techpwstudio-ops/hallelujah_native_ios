import Foundation

/// `GET /book/chapter/verses`'s full response (`book.controller.js`), mapped
/// into one value — verses plus whatever notes/highlights the server chose
/// to include (only sent when the request's `isBookNumberChanged`/
/// `isChapterNumberChanged` flags say the content actually changed; see
/// `BibleRepository.fetchChapter`). Also what `BibleChapterCache` persists
/// per chapter, letting a cache hit return the last-known notes/highlights
/// instantly rather than only the verse text.
struct BibleChapter: Sendable, Equatable, Codable {
    let bookNumber: Int
    let chapterNumber: Int
    let languageName: String
    let verses: [BibleVerse]
    let notes: [VerseNote]
    let highlights: [VerseHighlight]
}
