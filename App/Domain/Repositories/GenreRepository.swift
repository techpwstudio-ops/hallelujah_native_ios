import Foundation

/// T42 — the browse grid (`SearchPage`, `lib/views/search/search_page.dart`)
/// and a genre's own detail screen (`GenreSongs`,
/// `lib/views/search/category_songs.dart`). Genre metadata has no dedicated
/// single-item endpoint (`genre.controller.js` exports only `getGenres`/
/// `getGenreSongs`, confirmed directly) — `fetchGenres()` is the one source
/// both the grid and a detail screen's header resolve a genre's name/image
/// from.
protocol GenreRepository: Sendable {
    /// `Endpoint.dashboardInit`'s `genres` slice.
    func fetchGenres() async throws -> [Genre]

    /// `Endpoint.genreSongs(id:page:)`.
    func fetchSongs(genreID: String, page: Int) async throws -> Paginated<Song>
}
