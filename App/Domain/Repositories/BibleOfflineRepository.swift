import Foundation

/// T55 (offline bible and search) — `src/routes/user/book.routes.js`'s
/// `/book/search` and `/book/snapshot/trigger`, plus the public S3/CDN
/// snapshot `RemoteBibleOfflineRepository` reads directly. Deliberately
/// separate from `BibleRepository`: that protocol's own doc comment
/// excludes exactly this surface ("the CDN whole-language snapshot download,
/// the bulk `GET /book/verses` endpoint, or `GET /book/search`") as T55's
/// scope, not T54's.
protocol BibleOfflineRepository: Sendable {
    /// `GET /book/search`. Throws `BibleOfflineRepositoryError` on
    /// transport/HTTP failure. Callers own debouncing and dropping stale
    /// in-flight results — this call has no built-in cancellation.
    func search(query: String, languageName: String, limit: Int) async throws -> BibleSearchResponse

    /// One book's chapters from the public S3/CDN snapshot
    /// (`bible-db-snapshot/:language/:bookNumber.json`), decoded straight
    /// into `BibleChapter`s. `nil` chapters in the response (a partially
    /// translated Bible) are simply omitted, matching Dart's own skip.
    ///
    /// Throws `.notFound` for a 404/403 (S3 masks "doesn't exist" as
    /// "forbidden" for a language whose snapshot hasn't generated yet — see
    /// `bible_offline_service.dart`'s own comment on this) so the caller can
    /// fall back to `triggerSnapshotRegeneration`. Throws `.failed` for
    /// anything else that didn't come back as a usable snapshot.
    func fetchBookSnapshot(language: String, bookNumber: Int) async throws -> [BibleChapter]

    /// `POST /book/snapshot/trigger`. Returns `true` (202) once the backend
    /// has queued regeneration; the caller is responsible for polling
    /// `fetchBookSnapshot` afterward.
    func triggerSnapshotRegeneration(language: String) async throws -> Bool
}

enum BibleOfflineRepositoryError: Error, Sendable, Equatable {
    case notFound
    case failed(status: Int)
    case transport
}
