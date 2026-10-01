import Foundation

/// One verse hit from `GET /book/search` (T55) — `bible_search_result.dart`.
/// The same shape backs an exact reference match (`data.type` `verse` /
/// `chapter`), a free-text match (`data.type` `content`, where `score` is
/// set), and a "Recent" row persisted by `BibleRecentSearchStore`.
struct BibleSearchResult: Sendable, Equatable, Codable {
    let id: String?
    let bookNumber: Int
    let bookName: String
    let chapterNumber: Int
    let verseNumber: Int
    let text: String
    let languageName: String?

    /// Relevance for free-text (`content`) matches; `1.0` = exact substring.
    /// `nil` for exact reference matches and recents.
    let score: Double?

    /// Human-readable reference, e.g. "John 3:16".
    var reference: String { "\(bookName) \(chapterNumber):\(verseNumber)" }

    /// Dotted reference used on the reader's search cards, e.g.
    /// "Genesis . 52 . 3".
    var dotReference: String { "\(bookName) . \(chapterNumber) . \(verseNumber)" }

    /// Verse text prefixed with its number, e.g. "3. And he pressed…".
    var numberedText: String { "\(verseNumber). \(text)" }
}
