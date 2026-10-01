import Foundation

/// `Endpoint.search` (`SEARCH_API.md`, `SearchBloc._buildBody` in
/// `lib/blocs/search/bloc.dart`) — T40/T41's one data need. The endpoint
/// already supports `userPlaylistId` server-side, to exclude songs already
/// on that playlist — the add-to-playlist picker's own concern, previously
/// unused here, now wired up by T45.
protocol SearchRepository: Sendable {
    /// - Parameters:
    ///   - filter: `nil` for universal (all-tabs, overview) search.
    ///   - musicPage/episodePage/creatorPage/playlistPage: each section's own
    ///     next page to fetch — always sent, all four, matching
    ///     `Endpoint.search`'s own doc comment on why.
    ///   - userPlaylistId: `nil` for a plain search; T45's add-songs picker
    ///     passes a real id to exclude songs already on that playlist.
    func search(
        query: String,
        filter: SearchFilter?,
        musicPage: Int,
        episodePage: Int,
        creatorPage: Int,
        playlistPage: Int,
        userPlaylistId: String?
    ) async throws -> SearchResults
}
