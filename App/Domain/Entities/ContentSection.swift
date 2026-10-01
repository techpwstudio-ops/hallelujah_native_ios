import Foundation

/// One card in the "Continue Your Journey" mixed rail (`recentMixed`
/// viewType). Ports `RecentItem` (`lib/models/home_v2_section.dart`) — a
/// single card can point at a company playlist, an album, a season, a user
/// playlist, a creator, or a bare song, and `itemType` says which;
/// `title`/`subtitle`/`image` arrive already resolved by the server so the
/// UI renders one card shape and only switches on `itemType`.
struct RecentContentItem: Sendable, Equatable, Identifiable {
    let id: String
    /// `song` · `companyPlaylist` · `album` · `season` · `userPlaylist` · `creator`.
    let itemType: String
    let entityId: String?
    let title: String?
    let subtitle: String?
    let image: String?
    let imageVariants: String?
    let playedAt: Date?
    /// The track to resume on tap — present on every eligible row.
    let songId: String?
    /// `music`/`episode` — drives card shape, orthogonal to `itemType`
    /// (which says what the card opens).
    let contentType: String?

    var isSong: Bool { itemType == "song" }
    /// Falls back to `itemType` only for `season`, which is always a
    /// podcast container — every other `itemType` needs `contentType` to
    /// know its shape. Ports `RecentItem.isEpisode`.
    var isEpisode: Bool {
        if let contentType { return contentType == "episode" }
        return itemType == "season"
    }
    var isCreatorPlaylist: Bool { itemType == "album" || itemType == "season" }
    /// Ports `RecentItem.isCompanyPlaylist` — Dart's own version compares
    /// `itemType` to `"companyPlaylist"` twice (`itemType == 'companyPlaylist'
    /// || itemType == 'companyPlaylist'`), which reads like a copy-paste typo
    /// rather than an intentional second case; collapsed to the one real
    /// comparison rather than reproducing the duplicate.
    var isCompanyPlaylist: Bool { itemType == "companyPlaylist" }
}

/// A section's hydrated content, typed by its `viewType`. Grounded in
/// `car_play_service.dart`'s own `_flatSongViewTypes`/`_playlistViewTypes`/
/// `_creatorViewTypes`/`_creatorPlaylistViewTypes` sets — the one place
/// Dart writes down which entity type each `viewType` carries.
enum SectionContent: Sendable, Equatable {
    /// `trending`/`songs`/`recommended`/`listSongs`.
    case songs(Paginated<Song>)
    /// `creators`.
    case creators(Paginated<Creator>)
    /// `companyPlaylists`/`aiPlaylist`/`similarPlaylist`/`singleCompanyPlaylist`
    /// (`Playlist.owner == .company`) and `playlists`
    /// (`Playlist.owner == .creator`, Dart's "Top Albums"-style rail).
    case playlists(Paginated<Playlist>)
    /// `recentMixed` — heterogeneous, already-resolved cards. Paginated on
    /// the wire (`HOME_V2_API.md` §4's catalogue marks `recent` "yes", uiId
    /// `recent-all`) — despite looking like a fixed-size rail, it has real
    /// page-2+ content behind a "recent songs" see-all screen (T29).
    case recentItems(Paginated<RecentContentItem>)
    /// A `viewType` this layer doesn't map to a content entity at all —
    /// `verseOfDay` (Bible content, not song/creator/playlist — M9's
    /// concern) is the one known case today. Mirrors Dart's own
    /// graceful-degradation convention for exactly this
    /// (`car_play_service.dart`'s "skipping unrecognized viewType" log,
    /// `home_section_builder.dart`'s "empty box for unknown") rather than
    /// failing the whole section decode over one rail it can't render.
    case unsupported(viewType: String)
}

extension SectionContent {
    /// §7: pagination is driven by this, never `items.count` against some
    /// remembered total.
    var hasMore: Bool {
        switch self {
        case .songs(let page): return page.hasMore
        case .creators(let page): return page.hasMore
        case .playlists(let page): return page.hasMore
        case .recentItems(let page): return page.hasMore
        case .unsupported: return false
        }
    }

    var currentPage: Int {
        switch self {
        case .songs(let page): return page.page
        case .creators(let page): return page.page
        case .playlists(let page): return page.page
        case .recentItems(let page): return page.page
        case .unsupported: return 1
        }
    }

    /// `HomeFeedViewModel.loadMore(uiId:)` — appends a subsequently-fetched
    /// page's rows onto this page's, keeping `other`'s pagination meta
    /// (it's the newer one). Falls back to `other` wholesale on a case
    /// mismatch, which shouldn't happen: a rail's `viewType`, and so its
    /// `SectionContent` case, never changes page to page.
    func appending(_ other: SectionContent) -> SectionContent {
        switch (self, other) {
        case (.songs(let existing), .songs(let next)):
            return .songs(Paginated(
                items: existing.items + next.items, page: next.page, perPage: next.perPage,
                total: next.total, totalPages: next.totalPages, hasMore: next.hasMore
            ))
        case (.creators(let existing), .creators(let next)):
            return .creators(Paginated(
                items: existing.items + next.items, page: next.page, perPage: next.perPage,
                total: next.total, totalPages: next.totalPages, hasMore: next.hasMore
            ))
        case (.playlists(let existing), .playlists(let next)):
            return .playlists(Paginated(
                items: existing.items + next.items, page: next.page, perPage: next.perPage,
                total: next.total, totalPages: next.totalPages, hasMore: next.hasMore
            ))
        case (.recentItems(let existing), .recentItems(let next)):
            return .recentItems(Paginated(
                items: existing.items + next.items, page: next.page, perPage: next.perPage,
                total: next.total, totalPages: next.totalPages, hasMore: next.hasMore
            ))
        default:
            return other
        }
    }
}

/// One rail's identity plus its hydrated content. Deliberately NOT a port of
/// `HomeV2Section`'s full layout/hydrate/cache state machine (`loaded`/
/// `loading`/`stale`/`degraded`/skeleton-then-hydrate) — that lifecycle,
/// and the on-disk feed cache built on top of it, is T28's job (Home feed:
/// "cached-first load, shimmer placeholders"). This is the plain decoded
/// shape of one hydration response, for T28 to hold whatever state machine
/// it needs around.
struct ContentSection: Sendable, Equatable, Identifiable {
    let id: String
    let key: String
    let title: String
    let viewType: String
    let type: String
    let rank: Int
    let content: SectionContent
}

extension ContentSection {
    /// `HomeFeedViewModel.loadMore(uiId:)` — merges a freshly-fetched page
    /// onto this one, keeping this rail's own identity (`next` is expected
    /// to be the same uiId's later page, so its `title`/`rank`/etc. are
    /// redundant with this section's).
    func appending(_ next: ContentSection) -> ContentSection {
        ContentSection(
            id: id, key: key, title: title, viewType: viewType, type: type, rank: rank,
            content: content.appending(next.content)
        )
    }
}
