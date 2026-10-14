import Foundation
import Observation

/// Same shape as `FavouriteSongsViewModel`'s own private page struct.
private struct FavouriteArtistsPage: Sendable {
    var items: [Creator] = []
    var page = 0
    var hasMore = true
    var isLoading = false
}

/// Ports `FavouriteArtistPage` (`lib/views/library/grid_artists_favorite.dart`):
/// a paginated grid of already-followed creators. No checkbox/multi-select
/// or inline unfollow toggle on this screen — a direct read of its own grid
/// confirms every `CreatorGridItem` there is built with `showCheckBox:
/// false` (unlike some other creator grids in the app) — but cells are
/// still tappable (see `FavouriteArtistsView`'s own doc comment for that
/// grounding). The "+" add-creators action (`CreatorGridPage`) is out of
/// scope: that destination has no implementation anywhere in this app yet
/// (`AppRoute.creatorGrid`'s own route stub).
@MainActor
@Observable
final class FavouriteArtistsViewModel {
    private let type: HomeContentType
    private var page = FavouriteArtistsPage()
    private let repository: any FavouriteRepository
    private let logger = AppLogger(category: .content)

    init(songType: String?, container: DependencyContainer = .current) {
        self.type = songType.flatMap(HomeContentType.init(rawValue:)) ?? .all
        repository = container.resolve()
    }

    var creators: [Creator] { page.items }
    var isLoadingCreators: Bool { page.isLoading }
    var hasLoadedOnce: Bool { page.page > 0 }

    func onAppear() async {
        guard !hasLoadedOnce, !page.isLoading else { return }
        await loadMoreCreators()
    }

    func loadMoreCreatorsIfNeeded(currentItem: Creator) async {
        guard let index = page.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= page.items.count - 3 else { return }
        await loadMoreCreators()
    }

    func loadMoreCreators() async {
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        do {
            let result = try await repository.fetchFavouriteCreators(type: type, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
        } catch {
            logger.warning("favourite artists page load failed: \(error)")
            if page.page == 0 {
                page.page = 1
                page.hasMore = false
            }
        }
        page.isLoading = false
    }
}
