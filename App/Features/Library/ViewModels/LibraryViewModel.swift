import Foundation
import Observation

/// Same shape as `GenreSongsViewModel`'s private page struct — one merged,
/// paginated list.
private struct LibraryItemsPage: Sendable {
    var items: [LibraryEntry] = []
    var page = 0
    var hasMore = true
    var isLoading = false
}

/// Ports `LibraryBloc` (`library.dart`): the song-type filter row drives
/// both the quick-link tile counts (`LoadLibraryCountEvent`) and the merged
/// paginated list (`LoadLibraryEvent`/`LoadMoreLibraryEvent`) together —
/// `LibraryHomeView`'s `.task(id: viewModel.filter)` re-runs `load()`
/// whenever the filter changes, mirroring `SongTypeTopNavigationButton
/// .onTap` re-dispatching both events in Dart.
@MainActor
@Observable
final class LibraryViewModel {
    var filter: HomeContentType = .all
    private(set) var counts: LibraryCounts?
    private(set) var isLoadingCounts = false

    private var page = LibraryItemsPage()
    private let repository: any LibraryRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    var items: [LibraryEntry] { page.items }
    var isLoadingItems: Bool { page.isLoading }
    var hasLoadedOnce: Bool { page.page > 0 }

    /// Entry point for `.task(id: viewModel.filter)` on `LibraryHomeView` —
    /// fires once on first appearance and again on every filter change,
    /// resetting the merged list to page 1.
    func load() async {
        page = LibraryItemsPage()
        async let itemsVoid: Void = loadMoreItems()
        async let countsVoid: Void = loadCounts()
        _ = await (itemsVoid, countsVoid)
    }

    func refresh() async {
        await load()
    }

    func loadMoreItemsIfNeeded(currentItem: LibraryEntry) async {
        guard let index = page.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= page.items.count - 3 else { return }
        await loadMoreItems()
    }

    private func loadCounts() async {
        isLoadingCounts = true
        do {
            counts = try await repository.fetchCounts(songType: filter)
        } catch {
            logger.warning("library counts load failed: \(error)")
        }
        isLoadingCounts = false
    }

    private func loadMoreItems() async {
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        do {
            let result = try await repository.fetchItems(songType: filter, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
        } catch {
            logger.warning("library items page load failed: \(error)")
            // First page failed with no data to show yet: mark it attempted
            // so the view can fall through to an empty state rather than
            // spinning forever, same reasoning as `GenreSongsViewModel`.
            if page.page == 0 {
                page.page = 1
                page.hasMore = false
            }
        }
        page.isLoading = false
    }
}
