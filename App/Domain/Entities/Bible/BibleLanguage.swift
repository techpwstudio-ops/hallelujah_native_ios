import Foundation

/// One row of `GET /book/init`'s `bookLanguages` array (`book.controller.js`)
/// — a translation the reader can switch to. The wire also sends
/// `jsonUrl`/`status`/`createdAt`/`updatedAt`, all owned by T55's offline
/// snapshot download, not decoded here.
struct BibleLanguage: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let language: String
}
