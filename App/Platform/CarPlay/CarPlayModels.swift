import Foundation

/// T49–T51 — the value types the CarPlay layer passes between
/// `CarPlayContentProvider` (fetching/mapping, no UIKit) and
/// `CarPlayController` (templates, no networking). Keeping the two halves
/// apart means the mapping logic can be unit-tested without a CarPlay scene.

/// One tappable row — a song, or a container that drills into its own song
/// list. Ports the loosely typed `{id, title, artist, imageUrl, itemType,
/// queueIds}` maps the Flutter bridge handed `CarPlaySceneDelegate`, with the
/// `itemType` string replaced by a real enum.
struct CarPlayRow: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        /// Tap plays `songs[index]` with the whole `songs` array as the queue.
        case song(index: Int)
        case creator(id: String)
        case companyPlaylist(id: String)
        /// An album/season (`Playlist.owner == .creator`) — a different
        /// backend model, and so a different songs endpoint, than a company
        /// playlist.
        case creatorPlaylist(id: String)
        case userPlaylist(id: String)
        case genre(id: String)
        /// A server-resolved "Continue Your Journey" song card: the wire
        /// shape carries only an id, no playable `Song`.
        case recentSong(songID: String)
    }

    let id: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let kind: Kind

    var isCircularArtwork: Bool {
        if case .creator = kind { return true }
        return false
    }
}

/// A group of rows that share one queue: every `.song` row's `index` points
/// into `songs`. Rows of any other kind don't use the queue.
struct CarPlayRowGroup: Sendable, Equatable {
    var rows: [CarPlayRow]
    var songs: [Song]
    var source: QueueAttribution

    static func empty(source: QueueAttribution) -> CarPlayRowGroup {
        CarPlayRowGroup(rows: [], songs: [], source: source)
    }
}

/// One Home rail (`CPListImageRowItem`).
struct CarPlayRail: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let viewType: String
    let group: CarPlayRowGroup

    /// `viewType == "trending"` renders as a condensed grid, not a scrolling
    /// strip — matched on the wire value, not the (localised) title, same as
    /// the Dart delegate.
    var isTrendingGrid: Bool { viewType == "trending" }
}
