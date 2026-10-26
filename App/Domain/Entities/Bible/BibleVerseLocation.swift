import Foundation

/// Where a verse sits, so an annotation saved offline can be written into
/// the cached chapter that shows it.
struct BibleVerseLocation: Sendable, Equatable, Codable {
    let languageName: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
}
