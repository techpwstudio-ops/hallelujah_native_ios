import Foundation

/// `GET /book/search`'s `{ message, data }` envelope (`book.controller.js`'s
/// `searchBible`). `data.type` discriminates the four shapes modelled by
/// `BibleSearchResponse` — see `bible_search_response.dart` for the Dart
/// reference this mirrors field-for-field.
struct BibleSearchEnvelopeDTO: Decodable {
    let data: BibleSearchDataDTO
}

struct BibleSearchDataDTO: Decodable {
    let type: String?
    let query: String?
    let reference: BibleReferenceDTO?
    let verses: [BibleSearchResultDTO]?
    let book: BibleBookRefDTO?
    let note: String?
    let results: [BibleSearchResultDTO]?

    func toDomain() -> BibleSearchResponse {
        switch type {
        case "verse", "chapter":
            return .verse(
                type: type ?? "verse",
                reference: reference?.toDomain(),
                verses: (verses ?? []).map { $0.toDomain() }
            )
        case "book":
            guard let book else {
                return .empty(query: query ?? "")
            }
            return .book(book.toDomain(), note: note)
        case "content":
            return .content(query: query ?? "", results: (results ?? []).map { $0.toDomain() })
        default:
            return .empty(query: query ?? "")
        }
    }
}

struct BibleSearchResultDTO: Decodable {
    let id: String?
    let bookNumber: Int
    let bookName: String?
    let chapterNumber: Int
    let verseNumber: Int
    let text: String?
    let languageName: String?
    let score: Double?

    func toDomain() -> BibleSearchResult {
        BibleSearchResult(
            id: id,
            bookNumber: bookNumber,
            bookName: bookName ?? "",
            chapterNumber: chapterNumber,
            verseNumber: verseNumber,
            text: text ?? "",
            languageName: languageName,
            score: score
        )
    }
}

struct BibleReferenceDTO: Decodable {
    let bookName: String?
    let bookNumber: Int
    let chapterNumber: Int
    let verseStart: Int?
    let verseEnd: Int?

    func toDomain() -> BibleReference {
        BibleReference(
            bookName: bookName ?? "",
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            verseStart: verseStart,
            verseEnd: verseEnd
        )
    }
}

struct BibleBookRefDTO: Decodable {
    let bookName: String?
    let bookNumber: Int
    let chapters: Int

    func toDomain() -> BibleBookRef {
        BibleBookRef(bookName: bookName ?? "", bookNumber: bookNumber, chapters: chapters)
    }
}
