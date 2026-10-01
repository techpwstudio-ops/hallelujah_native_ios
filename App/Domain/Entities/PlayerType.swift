import Foundation

/// Mirrors Dart's `PlayerType` (`lib/blocs/player/state.dart:5-17`) — the
/// identity of what container/surface a queue came from. Composed with an
/// id into a `playerId` (`"<playerType>-<id>"`, `getPlayerId`,
/// `state.dart:19-24`) used for cross-cutting identity: now-playing
/// highlight, recommendation `excludeId`, and (T38) the backend's
/// `PlayHistory.lastSourceId`. No explicit raw values given — Swift's
/// implicit raw value for a `String`-backed case is the case name itself,
/// which already matches Dart's `.name` exactly (both camelCase).
enum PlayerType: String, Sendable, Equatable, Codable {
    case home
    case genre
    case album
    case season
    case userPlaylist
    case search
    case creator
    case invite
    case download
    case favourite
    case companyPlaylist

    /// `QueueSourceService.queueableTypes` (queue_source_service.dart:27-34,
    /// confirmed exhaustive by `test/queue_source_test.dart:14-58`):
    /// containers with a real id whose songs can be fetched and appended to
    /// a queue as a whole. `home`/`search`/`download`/`favourite`/`invite`
    /// are surfaces with no fetchable container behind them.
    var isQueueable: Bool {
        switch self {
        case .companyPlaylist, .album, .season, .genre, .userPlaylist, .creator:
            true
        case .home, .search, .invite, .download, .favourite:
            false
        }
    }
}
