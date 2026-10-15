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

    /// `translations`: per-book `[{id, bibleBookId, language, translatedName,
    /// isUserCorrected}]`; the reader shows `translate(currentLanguage)`.
    let translations: [BibleBookTranslationDTO]?

    /// `bookNumber`/`chapters` are nullable in the schema even though
    /// always populated in practice — mapped defensively, dropping any book
    /// missing either.
    func toDomain() -> BibleBook? {
        guard let bookNumber, let chapters else { return nil }
        return BibleBook(
            id: id,
            bookNumber: bookNumber,
            name: name,
            chapters: chapters,
            translations: (translations ?? []).map {
                BibleBookTranslation(language: $0.language, translatedName: $0.translatedName)
            }
        )
    }
}

struct BibleLanguageDTO: Decodable {
    let id: String
    let language: String

    func toDomain() -> BibleLanguage {
        BibleLanguage(id: id, language: language)
    }
}

struct BibleBookTranslationDTO: Decodable {
    let language: String?
    let translatedName: String?
}
