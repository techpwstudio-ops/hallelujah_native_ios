import Foundation

/// One entry of a book's `translations` array in `GET /book/init`
/// (`BibleBookTranslation`, `lib/models/bible_book.dart`).
struct BibleBookTranslation: Sendable, Equatable, Codable {
    let language: String?
    let translatedName: String?
}

/// One row of `GET /book/init`'s `books` array (`book.controller.js`) — a
/// canon book, e.g. "Genesis". `bookNumber`/`chapters` are nullable in the
/// schema but always populated in practice; `BibleBookDTO.toDomain()` drops
/// any row missing either rather than modeling that theoretical gap here.
struct BibleBook: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let bookNumber: Int
    let name: String
    let chapters: Int
    let translations: [BibleBookTranslation]

    init(id: String, bookNumber: Int, name: String, chapters: Int, translations: [BibleBookTranslation] = []) {
        self.id = id
        self.bookNumber = bookNumber
        self.name = name
        self.chapters = chapters
        self.translations = translations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        bookNumber = try container.decode(Int.self, forKey: .bookNumber)
        name = try container.decode(String.self, forKey: .name)
        chapters = try container.decode(Int.self, forKey: .chapters)
        translations = try container.decodeIfPresent([BibleBookTranslation].self, forKey: .translations) ?? []
    }

    /// `BibleBook.translate` (`lib/models/bible_book.dart`): the name in
    /// `language` (case-insensitive match), falling back to the canonical
    /// `name` when there is no translation or it has no `translatedName`.
    func translate(_ language: String?) -> String {
        guard let language else { return name }
        let wanted = language.lowercased()
        let found = translations.first { ($0.language ?? "").lowercased() == wanted }
        guard let translated = found?.translatedName else { return name }
        return translated
    }
}
