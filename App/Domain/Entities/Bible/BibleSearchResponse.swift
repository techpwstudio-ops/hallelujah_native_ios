import Foundation

/// A resolved Bible reference (single verse, verse range, or whole chapter)
/// carried by `BibleSearchResponse.verse`. `bible_search_response.dart`'s
/// `BibleReference`.
struct BibleReference: Sendable, Equatable, Codable {
    let bookName: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseStart: Int?
    let verseEnd: Int?
}

/// A book resolved from the query (a book name, or a reference whose
/// chapter/verse was out of range) carried by `BibleSearchResponse.book`.
/// `bible_search_response.dart`'s `BibleBookRef`.
struct BibleBookRef: Sendable, Equatable, Codable {
    let bookName: String
    let bookNumber: Int
    let chapters: Int
}

/// The four response shapes of `GET /book/search`, distinguished by
/// `data.type` (`bible_search_response.dart`'s `sealed class
/// BibleSearchResponse`, ported as a Swift enum since Dart's sealed-class
/// pattern matching and Swift's enum `switch` play the same role here).
enum BibleSearchResponse: Sendable, Equatable {
    /// An exact reference match — a single verse, a verse range, or a whole
    /// chapter (`type` is `"verse"` or `"chapter"`). The "I know what I want"
    /// fast path: jump the reader straight to the verse(s).
    case verse(type: String, reference: BibleReference?, verses: [BibleSearchResult])

    /// The query resolved to a book (a book name with no chapter, or a
    /// reference whose chapter/verse was out of range — then `note` is set).
    case book(BibleBookRef, note: String?)

    /// Free-text matches ranked by relevance (already sorted best-first).
    case content(query: String, results: [BibleSearchResult])

    /// No matches for the query.
    case empty(query: String)
}
