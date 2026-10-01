import Foundation

/// One row of `GET /book/init`'s `books` array (`book.controller.js`) — a
/// canon book, e.g. "Genesis". `bookNumber`/`chapters` are nullable in the
/// schema but always populated in practice; `BibleBookDTO.toDomain()` drops
/// any row missing either rather than modeling that theoretical gap here.
struct BibleBook: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let bookNumber: Int
    let name: String
    let chapters: Int
}
