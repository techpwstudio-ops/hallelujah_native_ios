import Foundation

// MARK: - Highlight sync

/// `POST /book/verse/highlight/sync`'s body (`book.controller.js`). T54's
/// scope cut is whole-verse granularity only — `wordIndexStart`/
/// `wordIndexEnd` are never sent, so this DTO omits them entirely rather
/// than encoding them as `nil`.
struct SyncHighlightRequestDTO: Encodable {
    let verseId: String
    let highlights: [HighlightColorEntryDTO]
}

struct SyncHighlightResponseDTO: Decodable {
    let message: String
    let data: VerseHighlightDTO?
}

// MARK: - Note sync

/// `POST /book/verse/notes/sync`'s body. `content` nil/empty deletes the
/// note server-side and returns `data: null`.
struct SyncNoteRequestDTO: Encodable {
    let verseId: String
    let content: String?
}

struct SyncNoteResponseDTO: Decodable {
    let message: String
    let data: VerseNoteDTO?
}

// MARK: - Share

/// `GET /book/verse/share/:id`'s response. Only `link` is needed by T54 —
/// `verseReference`/`verseText` are built client-side from the already-
/// loaded `BibleBook.name` + `BibleVerse` instead of parsing the server's
/// `title`/`description` strings.
struct ShareVerseResponseDTO: Decodable {
    let data: ShareVerseDataDTO
}

struct ShareVerseDataDTO: Decodable {
    let link: String
}
