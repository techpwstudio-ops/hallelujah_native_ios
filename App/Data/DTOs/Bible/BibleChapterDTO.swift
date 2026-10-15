import Foundation

/// `GET /book/chapter/verses`'s response (`book.controller.js`). `notes`/
/// `highlights` are only sent when at least one of the request's
/// `isBookNumberChanged`/`isChapterNumberChanged` flags is exactly `"true"`
/// — see `BibleRepository.fetchChapter`'s doc comment.
struct BibleChapterResponseDTO: Decodable {
    let message: String
    let chapterNumber: Int
    let languageName: String
    let bookNumber: Int
    let verses: [BibleVerseDTO]
    let notes: [VerseNoteDTO]?
    let highlights: [VerseHighlightDTO]?

    private enum CodingKeys: String, CodingKey {
        case message, chapterNumber, languageName, bookNumber, verses, notes, highlights
    }

    /// The server echoes `chapterNumber`/`bookNumber` straight from the query
    /// string, so they can arrive as `"1"` instead of `1` — accept both.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decode(String.self, forKey: .message)
        chapterNumber = try Self.lenientInt(c, .chapterNumber)
        languageName = try c.decode(String.self, forKey: .languageName)
        bookNumber = try Self.lenientInt(c, .bookNumber)
        verses = try c.decode([BibleVerseDTO].self, forKey: .verses)
        notes = try c.decodeIfPresent([VerseNoteDTO].self, forKey: .notes)
        highlights = try c.decodeIfPresent([VerseHighlightDTO].self, forKey: .highlights)
    }

    private static func lenientInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Int {
        if let n = try? c.decode(Int.self, forKey: key) { return n }
        let str = try c.decode(String.self, forKey: key)
        guard let n = Int(str.trimmingCharacters(in: .whitespaces)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not an integer: \(str)")
        }
        return n
    }
}

/// The wire's per-verse row carries no `bookNumber`/`languageName` of its
/// own — `bookNumber` is threaded in from the response envelope.
struct BibleVerseDTO: Decodable {
    let id: String
    let chapterNumber: Int
    let verseNumber: Int
    let text: String

    func toDomain(bookNumber: Int) -> BibleVerse {
        BibleVerse(id: id, bookNumber: bookNumber, chapterNumber: chapterNumber, verseNumber: verseNumber, text: text)
    }
}

struct VerseNoteDTO: Decodable {
    let id: String
    let verseId: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
    let content: String
    let updatedAt: String?
    let createdAt: String?

    func toDomain() -> VerseNote {
        VerseNote(id: id, verseId: verseId, content: content, createdAt: createdAt)
    }
}

/// One entry of a highlight's `highlights` array — `{color, text}`. T54
/// never sends or reads `text` (whole-verse granularity only), but the
/// field still round-trips through `Codable` since the request DTO reuses
/// this same shape.
struct HighlightColorEntryDTO: Codable {
    let color: String
    let text: String?
}

struct VerseHighlightDTO: Decodable {
    let id: String
    let verseId: String
    let highlights: [HighlightColorEntryDTO]?

    func toDomain() -> VerseHighlight? {
        guard let colorHex = highlights?.first?.color else { return nil }
        return VerseHighlight(id: id, verseId: verseId, colorHex: colorHex)
    }
}
