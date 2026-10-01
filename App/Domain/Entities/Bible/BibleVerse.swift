import Foundation

/// One verse of a chapter (`GET /book/chapter/verses`, `book.controller.js`).
/// The wire's per-verse row carries no `bookNumber`/`languageName` of its
/// own — those are threaded in from the response envelope by
/// `BibleVerseDTO.toDomain(bookNumber:)`.
struct BibleVerse: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
    let text: String
}
