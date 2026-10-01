import Foundation

/// `getSongsByUserPlaylist`'s response envelope (`userPlaylist.controller.js:
/// 684-761`): the playlist header and its first page of songs arrive
/// together in one call — confirmed directly against the controller, which
/// re-fetches the full `playlist` row as a sibling of `data` (the songs
/// array) rather than requiring a separate header fetch. `UserPlaylistDetailView`
/// uses this as its one round trip; a standalone `fetchPlaylist(id:)` still
/// exists below for `CreatePlaylistView`'s rename pre-fill, which needs just
/// the title before any song list is relevant.
struct UserPlaylistSongsPage: Sendable, Equatable {
    let playlist: UserPlaylist
    let songs: Paginated<Song>
}

/// Mirrors `UserPlaylistBloc`'s server calls (`lib/blocs/user_playlists/`)
/// against `userPlaylist.controller.js`'s 8 endpoints relevant to T45 —
/// reorder (`lib/models/user_playlist.dart` has no persisted order field at
/// all) and the song-menu-triggered "add to playlist" sheet are both out of
/// scope, per T45's own status-log entry.
///
/// `attachSongs`/`detachSongs` return `Void`, not the mutated playlist: the
/// real attach response is one of three shapes (200 with a fresh `playlist`,
/// 200 "no valid songs" with no `playlist`, or — a confirmed backend quirk —
/// 401 "all songs already in playlist" with no `playlist`), so a caller that
/// always reloads the current page afterward (mirroring the pull-based
/// refresh `UserPlaylistDetailViewModel` already needs in place of Dart's
/// realtime socket push) doesn't need the repository to reconcile that
/// three-way shape into one return value.
protocol UserPlaylistRepository: Sendable {
    func fetchPlaylists(page: Int) async throws -> Paginated<UserPlaylist>
    func fetchPlaylist(id: String) async throws -> UserPlaylist
    func createPlaylist(title: String, songID: String?) async throws -> UserPlaylist
    func renamePlaylist(id: String, title: String) async throws -> UserPlaylist
    func deletePlaylist(id: String) async throws
    func attachSongs(playlistID: String, songIDs: [String]) async throws
    func detachSongs(playlistID: String, songIDs: [String]) async throws
    func fetchSongs(playlistID: String, page: Int) async throws -> UserPlaylistSongsPage
}
