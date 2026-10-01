import Foundation

/// T56 — Verse of the day. Routes confirmed against `verseOfDay.routes.js`
/// and the mount point `app.use("/api/book/verse-of-day", userVerseOfDayRoutes)`
/// (`app.js:593`). `markVerseOfDayClicked(id:)` already exists in
/// `Endpoint.swift` (added for T66's push-tap routing) — not duplicated
/// here.
extension Endpoint {
    /// `GET /book/verse-of-day/history` — page-based, newest first.
    static func verseOfDayHistory(page: Int) -> Endpoint {
        .get("/book/verse-of-day/history?page=\(page)")
    }

    /// `GET /book/verse-of-day/mark-delivered/:id` — fired once per FCM
    /// push receipt (`topic == "verse_of_day"`), mirroring
    /// `fcm_service.dart`'s `handleFcm`.
    static func markVerseOfDayDelivered(id: String) -> Endpoint {
        .get("/book/verse-of-day/mark-delivered/\(id)")
    }

    /// `GET /book/verse-of-day/toggle-like/:id`.
    static func toggleVerseOfDayLike(id: String) -> Endpoint {
        .get("/book/verse-of-day/toggle-like/\(id)")
    }

    /// `POST /book/verse-of-day/comments`, body `{verseOfDayId, content}`.
    static let addVerseOfDayComment = Endpoint.post("/book/verse-of-day/comments")

    /// `GET /book/verse-of-day/comments/:id` — `:id` is the `verseOfDayId`.
    static func verseOfDayComments(verseOfDayId: String, page: Int) -> Endpoint {
        .get("/book/verse-of-day/comments/\(verseOfDayId)?page=\(page)")
    }

    /// `GET /book/verse-of-day/comments/toggle-like/:id` — `:id` is the
    /// comment id.
    static func toggleVerseOfDayCommentLike(commentId: String) -> Endpoint {
        .get("/book/verse-of-day/comments/toggle-like/\(commentId)")
    }

    /// `GET /book/verse-of-day/share/:id` (`deepLink.controller.js`'s
    /// `shareVerseOfDay`), same `{data: {link}}` envelope as
    /// `bibleVerseShare(id:)`.
    static func verseOfDayShare(id: String) -> Endpoint {
        .get("/book/verse-of-day/share/\(id)")
    }
}
