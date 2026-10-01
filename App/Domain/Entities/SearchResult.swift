import Foundation

/// `filterApiName` (`lib/enums/ui_type.dart`) — the four selectable tabs on
/// T40's search screen. `UiItemType.songs` has no case here: it is the
/// separate add-to-playlist "select content" flow's own filter
/// (`bloc.dart`'s `isSongs` branch), not one of `content_search_page.dart`'s
/// `_filterTypes`. Raw values are the wire strings `Endpoint.search` sends,
/// not required to match this enum's own (Swift-friendlier) case names.
enum SearchFilter: String, Sendable, CaseIterable, Equatable {
    case music, episode, creator, playlists

    var title: String {
        switch self {
        case .music: "Music"
        case .episode: "Episodes"
        case .creator: "Artists"
        case .playlists: "Playlists"
        }
    }
}

/// `Playlist Object`'s `ownerType` (`SEARCH_API.md`) — which songs endpoint a
/// tap resolves to, and which row widget renders it
/// (`playlist_search_item.dart`'s `PlaylistSearchItem.build`). Distinct from
/// `PlaylistOwner` (`Playlist.swift`): that type's `.creator(id:name:)` case
/// doesn't exist on the wire here, and neither of `Playlist`'s cases models
/// the backend's own `ownerType`/`owner` normalization (`playlistSearchResult.js`)
/// this wire shape is built from — see `SearchPlaylistResult`'s own doc
/// comment.
enum SearchPlaylistOwnerType: String, Sendable, Equatable, Codable {
    case user, company
}

/// One `playlists.data` row (`SEARCH_API.md`'s "Playlist Object"). A search
/// result is NOT a `Playlist` (`Playlist.swift`): that type's owner is either
/// `.company` or `.creator(id:name:)`, and neither case matches search's own
/// per-owner-kind shape — a dedicated type avoids forcing search's shape
/// through a mapping that would have to invent values `Playlist` doesn't have
/// anywhere to put. `Codable` because a tapped playlist is one of the three
/// kinds of row `RecentSearchStore` persists (see `RecentSearchEntry`) —
/// unlike `Song`/`Creator`, this type has no other codebase-wide meaning to
/// protect, so persisting it directly needs no separate snapshot step.
///
/// Only the fields either row widget actually renders or navigates with
/// (`user_playlist_list_item.dart`, `playlist_search_item.dart`'s
/// `_CompanyPlaylistSearchRow`) — `description`/`type`/`songsCount`/`plays`/
/// `createdAt`/`rank`/`savesCount` are all real wire fields (`SEARCH_API.md`'s
/// "rendering core") but confirmed unused by both, so they have no home
/// here. Unlike Dart's own two widgets — which hardcode a company row's
/// owner line to a client-side `$appName` constant rather than reading the
/// wire at all — this type keeps `owner.image` out (never rendered, on
/// either kind) but does read `owner.name` uniformly; see `ownerName`.
///
/// `id` alone is not a stable identity across the two owner kinds: Dart's own
/// `PlaylistSearchItem.keyFor` composes `"<ownerType>:<id>"` specifically
/// because a user playlist and a company playlist can collide on the same
/// raw id. This type doesn't need that string trick — `ownerType` already
/// carries the discriminator as a typed field — but `RecentSearchStore` and
/// any `ForEach` over a mixed list must key on `compositeID` (or the
/// equivalent `(ownerType, id)` pair), not `id` alone, to preserve the same
/// guarantee.
struct SearchPlaylistResult: Sendable, Equatable, Codable, Identifiable {
    let id: String
    let title: String?
    let image: String?
    let imageVariants: String?
    let ownerType: SearchPlaylistOwnerType
    /// The wire's flat `owner.name` (`playlistSearchResult.js`'s
    /// `toUserPlaylistResult`/`toCompanyPlaylistResult`) — populated for
    /// BOTH owner kinds by the backend itself, not just user-owned: a real
    /// user playlist's `owner.name` is `playlist.user.name`, and a company
    /// playlist's is `COMPANY_PLAYLIST_OWNER_NAME` (the app's own display
    /// name, computed server-side — the same string Dart's
    /// `_CompanyPlaylistSearchRow` hardcodes client-side as `$appName`
    /// instead of reading it). Deliberately NOT `user.fName`
    /// (`user_playlist.dart:50`'s `adminName` mapper): that field belongs to
    /// a different, older, pre-`owner`-normalization shape, and the backend
    /// utility's own doc comment names `owner.name` as the intended "what to
    /// render under the title" field for both kinds uniformly.
    let ownerName: String?
    /// User-owned only. `"public"` | `"private"`, rendered `.capitalized`
    /// after `ownerName` in the subtitle. Absent/`nil` on a company
    /// playlist — it has no visibility concept, and even where the raw row
    /// happens to carry one, `_CompanyPlaylistSearchRow` never renders it —
    /// a row's subtitle logic must gate this on `ownerType == .user`, not
    /// just on whether the field decoded.
    let visibility: String?

    /// `"<ownerType>:<id>"` — the collision-safe identity `RecentSearchStore`
    /// and mixed-list `ForEach`s should key on, mirroring what Dart's
    /// `PlaylistSearchItem.keyFor` achieves via string concatenation.
    var compositeID: String { "\(ownerType.rawValue):\(id)" }
}

/// One `creators.data` row (`SEARCH_API.md`'s "Creator Object"). Deliberately
/// not the shared `Creator` (`Creator.swift`): search's wire shape is a
/// strict subset (`id`/`name`/`displayName`/`image`/`imageVariants`/
/// `followersCount`/`followers`) of what `Creator` models for the rest of the
/// app, and nothing downstream of search needs the other ~15 fields — a
/// dedicated type avoids a 22-argument, mostly-nil `Creator(...)` call both
/// at decode time and when `RecentSearchStore` reconstructs a persisted row.
/// `Codable` for the same reason as `SearchPlaylistResult`.
struct SearchCreatorResult: Sendable, Equatable, Codable, Identifiable {
    let id: String
    let name: String?
    let image: String?
    let imageVariants: String?
    let followersCount: Int?
}

/// `topResult` (`SEARCH_API.md`): one item, typed by `topResult.type`. An
/// episode's `type` is still `"music"`/`"episode"` on the `Song` itself
/// (`Song.isEpisode`), so both collapse into `.song` here — there is no
/// separate "episode" case, matching how `music`/`episodes` are two
/// same-shaped `Song` sections rather than two different item kinds.
///
/// Not `Codable`: the top result is a live-search-only concept (Dart's own
/// recent-search history is keyed by tapped *item*, never by "was this a top
/// result" — see `RecentSearchEntry`), so it never needs to round-trip
/// through persistence.
enum SearchTopResultItem: Sendable, Equatable {
    case song(Song)
    case creator(SearchCreatorResult)
    case playlist(SearchPlaylistResult)
}

/// One `GET /api/search` response, decoded (`SearchResponseDTO.toDomain()`).
/// Every section is present even in a filtered response — the other three
/// just decode to `.empty` (`SEARCH_API.md`: filtered sections come back as
/// `{data: [], meta: {}}`, or the key can be absent entirely) — so a caller
/// never has to branch on which sections exist, only on whether each is
/// empty.
struct SearchResults: Sendable, Equatable {
    let topResult: SearchTopResultItem?
    let music: Paginated<Song>
    let episodes: Paginated<Song>
    let creators: Paginated<SearchCreatorResult>
    let playlists: Paginated<SearchPlaylistResult>

    static let empty = SearchResults(
        topResult: nil,
        music: .empty,
        episodes: .empty,
        creators: .empty,
        playlists: .empty
    )
}
