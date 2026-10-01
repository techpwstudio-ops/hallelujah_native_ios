import Foundation

/// A download's lifecycle state. Loosely mirrors `flutter_downloader`'s own
/// `DownloadTaskStatus` (`enqueued`/`running`/`complete`/`failed`/
/// `canceled`/`paused`, read via `MyDownloadTaskModel.status`'s raw index in
/// `lib/blocs/downloader/bloc.dart`) but drops `canceled` as a persisted
/// state — `DownloadEngine.cancel(songID:)` removes the task and its partial
/// file entirely rather than leaving a cancelled row behind, so there is
/// nothing for a `canceled` case to ever be read back from.
enum DownloadState: String, Sendable, Equatable, Codable {
    case queued, downloading, paused, completed, failed
}

/// One song's download, from enqueue through completion or failure.
/// Persisted by `DownloadCatalogStore` (Application Support, not
/// `Library/Caches` — see that type's own doc comment) so an in-progress or
/// finished download survives a force-quit and relaunch. Dart's
/// `MyDownloadTaskModel` (`lib/models/my_download_task.dart`) is the nearest
/// analog but is a thin wrapper around `flutter_downloader`'s own native
/// bookkeeping (`taskID`, `status` as a plugin-owned int); T46 replaces that
/// plugin with a native background `URLSession`, so this type owns the full
/// lifecycle itself instead of proxying a third party's.
///
/// Carries a denormalized snapshot of `Song`'s own display fields, captured
/// once at enqueue time. There is no local `Song` cache anywhere in this app
/// — `Database.swift`'s own doc comment: zero GRDB tables registered, plain
/// files handle downloads instead; `Song.swift`'s own doc comment: no local
/// content cache exists yet to flatten data for. So after a force-quit and
/// relaunch, the Downloads screen must be able to show title/artwork/genre
/// with zero network calls — these fields are what makes that possible, the
/// same reasoning `RecentSongSnapshot` (`RecentSearchStore.swift`) already
/// applies to search history.
struct DownloadTask: Sendable, Equatable, Identifiable, Codable {
    let songID: String
    var id: String { songID }

    var state: DownloadState
    var quality: AudioQuality
    var bytesWritten: Int64
    var totalBytes: Int64?

    /// Filename only, relative to `DownloadCatalogStore.downloadsDirectory`
    /// — never a full URL. A persisted absolute URL is not stable across
    /// app relaunches (the sandbox container path can change), so this is
    /// always resolved against the store's current `downloadsDirectory` at
    /// read time instead.
    var localFileName: String?

    var createdAt: Date
    var updatedAt: Date

    /// Re-associates a resumed background `URLSessionTask` after a
    /// relaunch, by matching against `URLSession(configuration:)
    /// .getAllTasks { }`'s `taskIdentifier`s.
    var urlSessionTaskIdentifier: Int?

    /// `song.title ?? "Untitled"` — same fallback `CreatorSongRow` already
    /// uses for a title-less song.
    var songTitle: String
    /// `song.displayImage`.
    var songArtworkPath: String?
    /// `song.displayImageVariants`.
    var songArtworkVariants: String?
    /// `song.primaryGenre?.name`.
    var songGenreName: String?
    /// `song.duration`.
    var songDurationSeconds: Int?
    /// `song.type` (`"music"`/`"episode"`).
    var songType: String?
}
