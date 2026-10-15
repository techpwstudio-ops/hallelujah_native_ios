import Foundation

/// Mirrors `VerseOfDayHistoryBloc`'s server calls
/// (`lib/blocs/verse_of_day_history/bloc.dart`) against
/// `verseOfDay.controller.js`'s endpoints, mounted at `/book/verse-of-day`
/// (`app.js:593`: `app.use("/api/book/verse-of-day", userVerseOfDayRoutes)`).
///
/// There is no "get today's verse" endpoint by design — `markDelivered`/
/// `markClicked` double as fetch-by-id, each returning the full `VerseOfDay`
/// in its response envelope. On the wire, delivery happens via FCM push
/// (`topic == "verse_of_day"`), not a poll; this repository has no
/// `fetchToday()` for that reason — whatever last arrived is what
/// `cachedVerse(id:)` returns.
protocol VerseOfDayRepository: Sendable {
    /// `GET /book/verse-of-day/history` — page-based, newest first.
    func fetchHistory(page: Int) async throws -> Paginated<VerseOfDay>

    /// `GET /book/verse-of-day/mark-delivered/:id` — called once per push
    /// receipt. Also the point at which this repository caches the verse
    /// locally, so `cachedVerse(id:)` can find it afterward.
    @discardableResult
    func markDelivered(id: String) async throws -> VerseOfDay

    /// `GET /book/verse-of-day/mark-clicked/:id` — called on notification
    /// tap / deep-link open. `data` can come back `null` (already-clicked
    /// races, confirmed against the controller), hence the optional return.
    /// Also caches the verse locally on success, same as `markDelivered`.
    @discardableResult
    func markClicked(id: String) async throws -> VerseOfDay?

    /// `GET /book/verse-of-day/toggle-like/:id`.
    @discardableResult
    func toggleLike(id: String) async throws -> VerseOfDay

    /// `POST /book/verse-of-day/comments`, body `{verseOfDayId, content}`.
    func addComment(verseOfDayId: String, content: String) async throws -> VerseOfDayComment

    /// `GET /book/verse-of-day/comments/:id` — `:id` here is the
    /// `verseOfDayId`, page-based, confirmed against
    /// `verseOfDay.routes.js`.
    func fetchComments(verseOfDayId: String, page: Int) async throws -> Paginated<VerseOfDayComment>

    /// `GET /book/verse-of-day/comments/toggle-like/:id`.
    @discardableResult
    func toggleCommentLike(commentId: String) async throws -> VerseOfDayComment

    /// `GET /book/verse-of-day/share/:id` (`deepLink.controller.js`'s
    /// `shareVerseOfDay`) — same `{data: {link}}` envelope `BibleRepository.
    /// shareVerse` decodes, reused rather than duplicated.
    func shareURL(id: String) async throws -> URL

    /// The on-device mirror of `getRealm().find<VerseOfDay>(id)`
    /// (`home_section_builder.dart`'s `_VerseOfDaySection`) — the Home
    /// card's only read, deliberately never triggering a network fetch of
    /// its own. `nil` until a push (`markDelivered`) or a tap
    /// (`markClicked`) has cached something for this id.
    func cachedVerse(id: String) async -> VerseOfDay?

    /// Writes a verse into the on-device mirror (`realm.add<VerseOfDay>(..., update: true)`):
    /// home-feed rows, share-link rows and realtime count patches.
    func store(_ verse: VerseOfDay) async
}
