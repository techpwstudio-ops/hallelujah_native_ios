import Foundation

/// `getFavoriteSongs`/`toggleSongFavorite` (`songs.controller.js`) and
/// `getFavoriteCreators` (`creators.controller.js`) — T44's data needs.
///
/// No `unfollow`/`follow`-style pair for creators here: `CreatorRepository`
/// (T30) already owns `follow(creatorId:)`/`unfollow(creatorId:)`, reused
/// as-is for any inline unfollow from a favourites screen — this protocol
/// only adds the one fetch T30 had no reason to build, a paginated list of
/// already-followed creators.
protocol FavouriteRepository: Sendable {
    /// `toggleSongFavorite` never returns a song-shaped payload on any
    /// branch (confirmed directly against the controller) — callers rebuild
    /// their own local `Song` copy via `Song.withFavorited(_:)` on success
    /// and revert it on failure, rather than decoding a fresh one back.
    func toggleSongFavorite(songId: String, isFavorited: Bool) async throws

    /// `getFavoriteSongs` — `type` defaults to `.all` server-side if omitted,
    /// but every call site here sends it explicitly.
    func fetchFavouriteSongs(type: HomeContentType, page: Int) async throws -> Paginated<Song>

    /// `getFavoriteCreators`.
    func fetchFavouriteCreators(type: HomeContentType, page: Int) async throws -> Paginated<Creator>
}
