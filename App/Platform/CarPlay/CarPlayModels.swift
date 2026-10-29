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

/// One slot in Now Playing's button row. A plain value so what the row holds
/// — which buttons exist, which glyph each wears, which are lit — can be
/// decided, compared and tested without a CarPlay scene; `CarPlayController`
/// turns each slot into a `CPNowPlayingImageButton`.
struct CarPlayNowPlayingButton: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case like
        case shuffle
        case repeatMode
        case sleepTimer
    }

    let kind: Kind
    /// SF Symbol name.
    let symbol: String
    /// Drawn lit by CarPlay: favourited, shuffle on, repeat on, timer running.
    let isSelected: Bool

    /// Only what the app can actually do, in display order: Like, Shuffle,
    /// Repeat and — for listeners whose plan includes it — Sleep Timer.
    /// CarPlay has five slots; the app has no playback-speed control, so
    /// nothing fills the rest.
    static func row(
        isFavorited: Bool,
        isShuffled: Bool,
        repeatMode: RepeatMode,
        offersSleepTimer: Bool,
        isSleepTimerRunning: Bool
    ) -> [CarPlayNowPlayingButton] {
        var buttons = [
            CarPlayNowPlayingButton(
                kind: .like,
                symbol: isFavorited ? "heart.fill" : "heart",
                isSelected: isFavorited
            ),
            CarPlayNowPlayingButton(kind: .shuffle, symbol: "shuffle", isSelected: isShuffled),
            // Repeat-one wears its own glyph; off and all share one and differ
            // only in whether it is lit.
            CarPlayNowPlayingButton(
                kind: .repeatMode,
                symbol: repeatMode == .one ? "repeat.1" : "repeat",
                isSelected: repeatMode != .off
            ),
        ]
        if offersSleepTimer {
            buttons.append(
                CarPlayNowPlayingButton(
                    kind: .sleepTimer,
                    symbol: isSleepTimerRunning ? "moon.zzz.fill" : "moon.zzz",
                    isSelected: isSleepTimerRunning
                )
            )
        }
        return buttons
    }
}

/// The slice of the playback queue CarPlay's Queue screen lists: the song
/// that is playing, then what follows it. Songs already played are left out —
/// in a car the screen answers "what's next", and Previous lives on Now
/// Playing.
struct CarPlayQueueWindow: Sendable, Equatable {
    /// Where `songs[0]` sits in the full queue, so a tapped row maps back to a
    /// queue index.
    let startIndex: Int
    /// The current song first, then up to `limit - 1` that follow it.
    let songs: [Song]

    /// `nil` when the queue points at no song.
    init?(queue: PlaybackQueue, limit: Int) {
        guard limit > 0, queue.songs.indices.contains(queue.currentIndex) else { return nil }
        startIndex = queue.currentIndex
        songs = Array(queue.songs[queue.currentIndex...].prefix(limit))
    }
}
