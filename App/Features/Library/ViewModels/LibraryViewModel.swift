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
    private var coverPollTask: Task<Void, Never>?

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
        startCoverPollIfNeeded()
    }

    func refresh() async {
        await load()
    }

    /// Re-fetches page 1 and swaps it into the loaded list WITHOUT clearing it
    /// first, so a playlist's new cover (or a playlist created/changed
    /// elsewhere) shows up with no flash and without losing the scroll
    /// position or any later pages already loaded. `refresh()` can't do that —
    /// it resets to an empty list.
    ///
    /// This is what `users.playlist.updated` (Dart: writes the Realm row, the
    /// list rebuilds off it) maps to here, and also the fallback for when that
    /// silent push never arrives — see `UserPlaylist.coverPollDelays`. Page 1
    /// is authoritative; rows after it are kept, minus any duplicates.
    func silentRefresh() async {
        guard hasLoadedOnce, !page.isLoading else { return }
        // The liked tiles too: these used to reload only on a filter change
        // or pull-to-refresh, so a like elsewhere never showed up here.
        async let countsVoid: Void = loadCounts()
        await silentRefreshItems()
        await countsVoid
    }

    private func silentRefreshItems() async {
        let requestedFilter = filter
        let result: Paginated<LibraryEntry>
        do {
            result = try await repository.fetchItems(songType: requestedFilter, page: 1)
        } catch {
            logger.warning("library silent refresh failed: \(error)")
            return
        }
        // A filter change or reload began while this was in flight — stale.
        guard filter == requestedFilter, !page.isLoading else { return }

        let freshIDs = Set(result.items.map(\.id))
        let tail = page.items.dropFirst(result.items.count).filter { !freshIDs.contains($0.id) }
        page.items = result.items + tail
        if page.page <= 1 {
            page.page = result.page
            page.hasMore = result.hasMore
        }
        startCoverPollIfNeeded()
    }

    /// Cancels the cover re-checks; the view calls this when it leaves screen.
    func stopCoverPoll() {
        coverPollTask?.cancel()
        coverPollTask = nil
    }

    /// A playlist that has songs but still shows the letter tile is waiting on
    /// its server-built cover. Re-checks on `UserPlaylist.coverPollDelays`
    /// until none is waiting, instead of relying on the best-effort push alone.
    private var hasCoverPending: Bool {
        page.items.contains { entry in
            guard case let .userPlaylist(_, _, image, _, songsCount, _, _) = entry else { return false }
            return (songsCount ?? 0) > 0 && DefaultThumbnail.isLetterTile(path: image)
        }
    }

    private func startCoverPollIfNeeded() {
        guard coverPollTask == nil, hasCoverPending else { return }
        coverPollTask = Task { [weak self] in
            for delay in UserPlaylist.coverPollDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                await self.silentRefresh()
                if !self.hasCoverPending { break }
            }
            // A cancelled run was already cleared (and maybe replaced) by
            // `stopCoverPoll()`; only a run that finished on its own clears itself.
            if !Task.isCancelled { self?.coverPollTask = nil }
        }
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
