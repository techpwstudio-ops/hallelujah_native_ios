import Foundation

/// `GET /book/init`'s response (`book.controller.js`).
struct BibleInitResponseDTO: Decodable {
    let message: String
    let books: [BibleBookDTO]
    let bookLanguages: [BibleLanguageDTO]
}

struct BibleBookDTO: Decodable {
    let id: String
    let name: String
    let chapters: Int?
    let bookNumber: Int?

    // `translations` (per-book `[{id, bibleBookId, language, translatedName,
    // isUserCorrected}]`) exists on the wire but is intentionally not
    // decoded — T54 always renders `BibleBook.name` (the canonical English
    // name); resolving a per-user translated name needs the user's
    // content-language preference threaded through, a cross-cutting concern
    // owned elsewhere, not this endpoint's contract. Scope cut.

    /// `bookNumber`/`chapters` are nullable in the schema even though
    /// always populated in practice — mapped defensively, dropping any book
    /// missing either.
    func toDomain() -> BibleBook? {
        guard let bookNumber, let chapters else { return nil }
        return BibleBook(id: id, bookNumber: bookNumber, name: name, chapters: chapters)
    }
}

struct BibleLanguageDTO: Decodable {
    let id: String
    let language: String

    func toDomain() -> BibleLanguage {
        BibleLanguage(id: id, language: language)
    }
}
