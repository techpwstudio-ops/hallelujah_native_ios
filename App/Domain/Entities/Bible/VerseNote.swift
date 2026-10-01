import Foundation

/// A verse's user note (`POST /book/verse/notes/sync`, `book.controller.js`).
struct VerseNote: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let verseId: String
    let content: String
}
