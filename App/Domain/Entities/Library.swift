import Foundation

/// One row of the merged Library list (`GET /library/items`,
/// `library.controller.js`'s `getLibraryItems`): the backend already merges
/// owned/followed user playlists with creator- and company-owned playlists
/// the caller has saved, sorted by `addedAt` desc. `.playlist` covers both
/// `creatorPlaylist`/`companyPlaylist` rows — both map onto the existing
/// `Playlist` domain entity (`PlaylistOwner.creator`/`.company`) — while
/// `.userPlaylist` stays a bare id/title/image tuple: no `UserPlaylist`
/// domain model exists yet (that's T45's job), same reasoning
/// `AppRoute.userPlaylistSongs` already documents for staying id-only.
enum LibraryEntry: Sendable, Identifiable, Equatable {
    case playlist(Playlist)
    case userPlaylist(id: String, title: String, image: String?, imageVariants: String?, songsCount: Int?, isOwner: Bool, detail: String? = nil)

    var id: String {
        switch self {
        case let .playlist(playlist): playlist.id
        case let .userPlaylist(id, _, _, _, _, _, _): id
        }
    }
}

/// `GET /library/content/count/:type`'s three fields this screen actually
/// uses (`library.controller.js`'s `getLibraryCount`) — `playlists`/
/// `savedItems` are dropped here the same way `library.dart`'s own bloc
/// never reads them either (confirmed dead even in the Dart reference).
struct LibraryCounts: Sendable, Equatable {
    let likedMusic: Int
    let likedEpisodes: Int
    let likedArtists: Int
}
