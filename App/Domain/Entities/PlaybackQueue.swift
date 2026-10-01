import Foundation

/// A queue's attribution: which container/surface it came from. Mirrors
/// `_basePlayerType`/`_basePlayerId`/`_baseContextTitle`
/// (`lib/blocs/player/bloc.dart:206-208`) — set once per `PlaySongEvent`
/// and read by "playing from X" UI and (T38) analytics — NOT Dart's
/// narrower `QueueSource` type (`lib/models/queue_source.dart`), which only
/// exists for "append a whole container to the queue" and has no native
/// equivalent yet (deferred alongside that feature — see `QueueController`'s
/// doc comment).
struct QueueAttribution: Sendable, Equatable {
    let playerType: PlayerType
    /// The container's own id, or `nil` for a surface with no container
    /// (`home`/`search` pass a `null` model id to `getPlayerId` in Dart).
    let id: String?
    let title: String

    /// `getPlayerId` (`lib/blocs/player/state.dart:19-24`): `"<playerType>-<id ?? "">"`.
    var playerID: String {
        "\(playerType.rawValue)-\(id ?? "")"
    }
}

/// The canonical, ordered playback queue — one flat array, mutated in place
/// for reorder (no separate shuffled-view type layered on top; when
/// shuffled, `songs` itself IS the shuffled order). Mirrors
/// `PlayerBlocState.songIdList`/`currentSongIndex`
/// (`lib/blocs/player/state.dart`), except this carries full `Song` objects
/// rather than bare ids — this codebase has no local content cache to
/// resolve a bare id against, the same reasoning T29's `PlaylistDetailView`
/// already established for taking a full `Playlist` rather than an id.
struct PlaybackQueue: Sendable, Equatable {
    var songs: [Song]
    var currentIndex: Int
    var source: QueueAttribution

    var currentSong: Song? {
        songs.indices.contains(currentIndex) ? songs[currentIndex] : nil
    }
}
