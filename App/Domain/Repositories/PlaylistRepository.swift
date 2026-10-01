import Foundation

/// `getPlaylistSongs`/`getCompanyPlaylistSongs` (`end_points.dart`) — a
/// playlist's own song list (T29's "album songs"/"company playlist songs"
/// screens). Two different endpoints on the wire, unified into one method
/// here the same way T27 already unified `CompanyPlaylist`/`CreatorPlaylist`
/// into one `Playlist` with an `owner`: the call site just has a `Playlist`
/// and shouldn't need to know which backend model it came from.
protocol PlaylistRepository: Sendable {
    /// `owner` picks the endpoint (`.company` → `/company-playlist/:id/songs`,
    /// `.creator` → `/playlist/:id/songs`) — both page with the same older
    /// `{page, perPage, totalPages, count}` meta shape `CreatorRepository`
    /// already grounds `hasMore`'s derivation against.
    func fetchSongs(playlistId: String, owner: PlaylistOwner, page: Int) async throws -> Paginated<Song>
}
