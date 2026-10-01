import Foundation

/// Dart has two near-identical Realm models for a curated set of songs —
/// `CompanyPlaylist` (company-curated; `type` doubles as "Album"/"Season"
/// when it's one of those) and `CreatorPlaylist` (a creator's own curated
/// set — `car_play_service.dart`'s own comment calls its `playlists`
/// viewType rail "Curated/album rails... e.g. 'Top Albums'"). They differ
/// only in whether a creator owns the playlist; everything else — id,
/// title, image, songsCount, type/visibility — is the same shape. Unified
/// here as one `Playlist` with an `owner`, rather than inventing a separate
/// native "Album" type Dart itself doesn't have (an Album IS a `Playlist`
/// with `type == "album"`) or duplicating the Realm split natively.
///
/// `UserPlaylist` (a signed-in user's own library playlist — `isFollowed`,
/// a raw song-id list, reached only from Library) is a different concept —
/// left to T45 (User playlists), not this task.
enum PlaylistOwner: Sendable, Equatable {
    case company
    case creator(id: String?, name: String?)
}

struct Playlist: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let image: String?
    let imageVariants: String?
    /// `CompanyPlaylist.type`/`CreatorPlaylist.type` — e.g. `"album"`,
    /// `"season"`, or nil for a plain playlist.
    let type: String?
    let visibility: String?
    let language: String?
    let songsCount: Int?
    /// Total duration in seconds. `CreatorPlaylist` only — its own JSON
    /// parser (`getCreatorPlaylistFromJson`) reads this but, despite the
    /// Realm model also declaring a `plays` field, never reads a `plays`
    /// key from the API response at all, so no `plays` field is ported
    /// here either — there is nothing to ground it in.
    let duration: Int?
    /// `CompanyPlaylist` only — its curated ordering.
    let rank: Int?
    let owner: PlaylistOwner
    let createdAt: Date?
    let updatedAt: Date?
    /// `similarPlaylist` rows only (`HOME_V2_API.md` §6.4) — `true` for the
    /// one row the "More Like X" rail is about, which the API returns as
    /// `data[0]` rather than a separate field alongside the array. `false`
    /// for every row from every other rail.
    let isSeed: Bool

    /// `type` is the wire's `SongType` column (`"music"`/`"episode"`), not the
    /// literal strings `"album"`/`"season"` this pair's naming suggests — a
    /// prior ambiguity `CreatorPlaylistRow.swift`'s own doc comment flagged
    /// as unresolved between two candidate readings. Resolved here (T43)
    /// against `_SavedItemRow._resolve()` (`library_list_item.dart`), the one
    /// real Dart call site that actually branches on a creator playlist's
    /// Album/Season identity: `isSeason = playlist.type ==
    /// SongType.episode.name`, binary — never a third "neither" case —
    /// confirmed against the wire itself (`Playlist`/`CompanyPlaylist.type`
    /// in `prisma/schema.prisma` is the `SongType` enum column, and
    /// `library.controller.js`'s `type` query param filters on the same).
    var isSeason: Bool { type == "episode" }
    var isAlbum: Bool { !isSeason }
}
