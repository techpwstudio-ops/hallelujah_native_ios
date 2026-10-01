import Foundation

/// Ports the two `LibraryBloc` reads `library.dart` actually issues:
/// `LoadLibraryCountEvent` and `LoadLibraryEvent`/`LoadMoreLibraryEvent`.
/// Both are scoped by the same `SongType` filter the screen's own top nav
/// row drives (`HomeContentType` here — already exactly the three values
/// Dart's `SongType` has).
protocol LibraryRepository: Sendable {
    func fetchCounts(songType: HomeContentType) async throws -> LibraryCounts
    func fetchItems(songType: HomeContentType, page: Int) async throws -> Paginated<LibraryEntry>
}
