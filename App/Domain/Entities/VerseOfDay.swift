import Foundation

/// T56 — a daily verse push. Ports the Flutter app's `VerseOfDay` Realm model
/// (`lib/models/verse_of_day.dart`), backed by `verseOfDay.controller.js`
/// (`GET /book/verse-of-day/...`). Unlike most content entities here, there
/// is no dedicated "fetch today's verse" endpoint — the mark-delivered/
/// mark-clicked endpoints double as fetch-by-id, returning this same shape
/// in their `data` envelope (see `VerseOfDayRepository`'s doc comment).
struct VerseOfDay: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let title: String?
    let deliveryStatus: String?
    let image: String?
    let backgroundImage: String?
    let verseId: String?
    let languageName: String?
    let verseText: String?
    let bookName: String?
    let bookNumber: Int?
    let chapterNumber: Int?
    let verseNumber: Int?
    let likes: Int
    let shares: Int
    let comments: Int
    /// `isLinked` on the wire (`verseOfDay.controller.js`) — whether the
    /// current user's own like/favorite row exists, not a hyperlink flag.
    /// Renamed here to say what it actually means.
    let isLiked: Bool
    let scheduledAt: Date?
    let sentAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    /// `Genesis 1:3` — the reference this verse's `bookName`/`chapterNumber`/
    /// `verseNumber` point at, or `nil` if any of the three is missing.
    /// Mirrors the same "chapter:verse" shape `VerseInsightRequest` builds
    /// for the Bible reader.
    var reference: String? {
        guard let bookName, let chapterNumber, let verseNumber else { return nil }
        return "\(bookName) \(chapterNumber):\(verseNumber)"
    }

    /// This verse as it looks right after the user taps the heart: like
    /// flipped, count moved by one. The card shows it straight away and the
    /// server's answer replaces it.
    func withLikeToggled() -> VerseOfDay {
        let liked = !isLiked
        return VerseOfDay(
            id: id, title: title, deliveryStatus: deliveryStatus, image: image,
            backgroundImage: backgroundImage, verseId: verseId, languageName: languageName,
            verseText: verseText, bookName: bookName, bookNumber: bookNumber,
            chapterNumber: chapterNumber, verseNumber: verseNumber,
            likes: max(0, likes + (liked ? 1 : -1)), shares: shares, comments: comments,
            isLiked: liked, scheduledAt: scheduledAt, sentAt: sentAt,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
