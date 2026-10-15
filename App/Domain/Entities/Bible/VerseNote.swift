import Foundation

/// A verse's user note (`POST /book/verse/notes/sync`, `book.controller.js`).
struct VerseNote: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let verseId: String
    let content: String
    /// Server `createdAt` (ISO-8601), when the response carried one — the
    /// date the Notes list shows and sorts by (`Formater.formatToDate(createdAt)`).
    var createdAt: String? = nil
}
