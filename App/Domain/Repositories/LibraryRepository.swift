import Foundation

/// Ports the two `LibraryBloc` reads `library.dart` actually issues:
/// `LoadLibraryCountEvent` and `LoadLibraryEvent`/`LoadMoreLibraryEvent`.
/// Both are scoped by the same `SongType` filter the screen's own top nav
/// row drives (`HomeContentType` here — already exactly the three values
/// Dart's `SongType` has).
protocol LibraryRepository: Sendable {
    func fetchCounts(songType: HomeContentType) async throws -> LibraryCounts
    func fetchItems(songType: HomeContentType, page: Int) async throws -> Paginated<LibraryEntry>

    /// `GET /library/items/ids` — every saved item as `"<type>:<id>"`.
    /// Small, fetched once per session, read by every save toggle.
    func fetchSavedKeys() async throws -> Set<String>

    /// `POST /library/items/:type/:id/toggle`. Returns the server's verdict
    /// (`data.inLibrary`), which wins over the caller's optimistic guess when
    /// the item was toggled from another device in between.
    func toggleSaved(type: LibraryItemType, id: String) async throws -> Bool
}
