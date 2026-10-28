import Foundation

/// `getCreatorApi`/`getCreatorSongsApi`/`getCreatorPlaylistsApi`/
/// `followCreatorApi`/`unfollowCreatorApi` (`end_points.dart:162-168`) — the
/// creator-profile screen's data needs (T30). A single creator's own detail
/// plus their catalogue, distinct from `HomeRepository`'s home-rail concern.
protocol CreatorRepository: Sendable {
    func fetchCreator(id: String) async throws -> Creator

    /// `getCreatorSongsApi`/`getCreatorPlaylistsApi` both page with the
    /// OLDER `{page, perPage, totalPages, count}` meta shape
    /// (`PaginationModel.fromJson`, `lib/models/CategoryPageData.dart`) —
    /// distinct from the V2 home feed's `hasMore`-carrying envelope
    /// `Paginated<T>` itself is grounded in. `hasMore` here is derived
    /// (`page < totalPages`), same as Dart's own `PaginationModel.hasNextPage`.
    func fetchSongs(creatorId: String, type: HomeContentType, page: Int) async throws -> Paginated<Song>
    func fetchPlaylists(creatorId: String, type: HomeContentType, page: Int) async throws -> Paginated<Playlist>

    /// `attachCreators`/`detachCreator` (`lib/blocs/favourite/bloc.dart`) —
    /// both send the whole request as `ids: [creatorId]` even for a
    /// single-creator toggle. Throws only when the server refuses; returns
    /// the creator's row when the response happens to include it. Each
    /// success is recorded in `CreatorFollowStore`, which every follow
    /// button reads, so all screens agree.
    @discardableResult
    func follow(creatorId: String) async throws -> Creator?
    @discardableResult
    func unfollow(creatorId: String) async throws -> Creator?
    /// `detachCreator(ids)` for several at once (the artists grid's "Done").
    func unfollow(creatorIds: [String]) async throws

    /// `CreatorsBloc._load` (`getCreatorsApi`) — every creator, for the
    /// "Choose artists you like." grid.
    func fetchAllCreators(page: Int) async throws -> Paginated<Creator>

    /// `FavouriteBloc.attachCreators(ids, sync: true)` — `detach: true` makes
    /// the server replace the followed set with exactly `ids` (the grid's
    /// "Done" button); `detach: false` only adds. The grid sends only what
    /// changed (`detach: false` + `unfollow(creatorIds:)`), since its view of
    /// the followed set can be partial.
    func setFollowedCreators(ids: [String], replacingExisting: Bool) async throws
}
