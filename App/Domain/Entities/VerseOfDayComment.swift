import Foundation

/// T56 — a comment on a `VerseOfDay`. Ports the Flutter app's
/// `VerseOfDayComment` Realm model (`lib/models/verse_of_day_comment.dart`),
/// which flattens the wire's nested `user.{name,image,imageVariants}` object
/// into these three top-level fields at parse time — this entity does the
/// same, matching `commentToVerseOfDay`/`getVerseOfDayComments`
/// (`verseOfDay.controller.js`).
struct VerseOfDayComment: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let verseOfDayId: String
    let content: String
    let userId: String?
    let userName: String?
    let userImage: String?
    let userImageVariants: String?
    let likes: Int
    /// `isLinked` on the wire — the current user's own like row, not a
    /// hyperlink. Same rename `VerseOfDay.isLiked` documents.
    let isLiked: Bool
    let createdAt: Date?
    let updatedAt: Date?
}
