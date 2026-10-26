import Foundation

/// `GET /book/chapter/verses`'s response (`book.controller.js`). `notes`/
/// `highlights` are only sent when at least one of the request's
/// `isBookNumberChanged`/`isChapterNumberChanged` flags is exactly `"true"`
/// — see `BibleRepository.fetchChapter`'s doc comment.
struct BibleChapterResponseDTO: Decodable {
    let message: String?
    /// `nil` when the server leaves them out — the repository falls back to
    /// what it asked for.
    let chapterNumber: Int?
    let languageName: String?
    let bookNumber: Int?
    let verses: [BibleVerseDTO]
    let notes: [VerseNoteDTO]?
    let highlights: [VerseHighlightDTO]?

    private enum CodingKeys: String, CodingKey {
        case message, chapterNumber, languageName, bookNumber, verses, notes, highlights
    }

    /// Lenient on purpose. Chapter navigation silently stayed on the same
    /// chapter whenever any one field of the response didn't match this
    /// shape exactly (a numeric field sent as a string, a malformed note or
    /// highlight on one verse): the whole chapter failed to decode and the
    /// reader kept what was on screen. Now only the bad row is dropped. The
    /// server echoes `chapterNumber`/`bookNumber` straight from the query
    /// string, so they can arrive as `"1"` instead of `1`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        chapterNumber = LenientInt.decode(c, .chapterNumber)
        languageName = try? c.decodeIfPresent(String.self, forKey: .languageName)
        bookNumber = LenientInt.decode(c, .bookNumber)
        verses = (try? c.decodeIfPresent([Lossy<BibleVerseDTO>].self, forKey: .verses))?.compactMap(\.value) ?? []
        notes = (try? c.decodeIfPresent([Lossy<VerseNoteDTO>].self, forKey: .notes))?.compactMap(\.value)
        highlights = (try? c.decodeIfPresent([Lossy<VerseHighlightDTO>].self, forKey: .highlights))?.compactMap(\.value)
    }
}

/// One element of an array that may fail to decode on its own without
/// failing the whole array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// An `Int` the server may send as a number or a numeric string.
enum LenientInt {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let n = try? c.decode(Int.self, forKey: key) { return n }
        if let str = try? c.decode(String.self, forKey: key) {
            return Int(str.trimmingCharacters(in: .whitespaces))
        }
        if let d = try? c.decode(Double.self, forKey: key) { return Int(d) }
        return nil
    }
}

/// The wire's per-verse row carries no `bookNumber`/`languageName` of its
/// own — `bookNumber` is threaded in from the response envelope.
struct BibleVerseDTO: Decodable {
    let id: String
    let chapterNumber: Int
    let verseNumber: Int
    let text: String

    private enum CodingKeys: String, CodingKey {
        case id, chapterNumber, verseNumber, text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        guard let verseNumber = LenientInt.decode(c, .verseNumber) else {
            throw DecodingError.dataCorruptedError(forKey: .verseNumber, in: c, debugDescription: "missing verseNumber")
        }
        self.verseNumber = verseNumber
        chapterNumber = LenientInt.decode(c, .chapterNumber) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }

    func toDomain(bookNumber: Int, fallbackChapter: Int) -> BibleVerse {
        BibleVerse(
            id: id,
            bookNumber: bookNumber,
            chapterNumber: chapterNumber > 0 ? chapterNumber : fallbackChapter,
            verseNumber: verseNumber,
            text: text
        )
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

/// One entry of a highlight's `highlights` array — `{index, id, color}`
/// (`HighlightedWordModel.toJson`): one word of the verse and its colour. An
/// entry without `index` is the whole-verse form. `text` is a legacy field
/// that is never sent. Nil fields are omitted when encoding.
struct HighlightColorEntryDTO: Codable {
    let color: String
    let text: String?
    let index: Int?
    let id: String?

    init(color: String, text: String? = nil, index: Int? = nil, id: String? = nil) {
        self.color = color
        self.text = text
        self.index = index
        self.id = id
    }
}

struct VerseHighlightDTO: Decodable {
    let id: String
    let verseId: String
    let highlights: [HighlightColorEntryDTO]?

    func toDomain() -> VerseHighlight? {
        let words = (highlights ?? []).map { VerseHighlight.Word(index: $0.index, colorHex: $0.color) }
        guard !words.isEmpty else { return nil }
        return VerseHighlight(id: id, verseId: verseId, words: words)
    }
}
