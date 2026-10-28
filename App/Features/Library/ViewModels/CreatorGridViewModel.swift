import Foundation
import Observation

/// Ports `CreatorGridPage` (`lib/views/library/grid_artists.dart`)'s state:
/// the paginated all-creators list (`CreatorsBloc`), the favourites snapshot
/// taken on entry (`_initialFavouriteIds`) and the in-flight selection
/// (`SelectContentBloc`). "Done" follows what was checked and un-follows
/// what was unchecked (see `done()` for why not Dart's whole-set replace).
@MainActor
@Observable
final class CreatorGridViewModel {
    private(set) var creators: [Creator] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var hasLoadedOnce = false
    private(set) var isSaving = false
    private(set) var initialSelection: Set<String> = []
    private(set) var selection: Set<String> = []

    private var page = 0
    private let repository: any CreatorRepository
    private let favourites: any FavouriteRepository
    private let songType: HomeContentType
    private let logger = AppLogger(category: .content)

    init(songType: String, container: DependencyContainer = .current) {
        self.songType = HomeContentType(rawValue: songType) ?? .all
        repository = container.resolve()
        favourites = container.resolve()
    }

    /// Selection differs from what was followed on entry (drives the
    /// floating "Done" button).
    var hasChanges: Bool { selection != initialSelection }

    func onAppear() async {
        guard !hasLoadedOnce else { return }
        await loadInitialSelection()
        await loadMore()
    }

    func refresh() async {
        guard !isLoading else { return }
        page = 0
        hasMore = true
        creators = []
        await loadMore()
    }

    func loadMoreIfNeeded(currentItem: Creator) async {
        guard let index = creators.firstIndex(where: { $0.id == currentItem.id }),
              index >= creators.count - 3 else { return }
        await loadMore()
    }

    func toggle(_ creator: Creator) {
        guard let id = creator.creatorId else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func isSelected(_ creator: Creator) -> Bool {
        creator.creatorId.map(selection.contains) ?? false
    }

    /// `true` when the server accepted the new set; the caller pops.
    func done() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        // Only what changed. Dart replaces the whole followed set
        // (`detach: true`) because its snapshot is every followed artist;
        // this one is loaded for one content type (and can come back short
        // if a page fails), so a replace silently un-followed every artist
        // missing from it — e.g. all podcast artists after "Done" here.
        let added = selection.subtracting(initialSelection).sorted()
        let removed = initialSelection.subtracting(selection).sorted()
        do {
            if !added.isEmpty {
                try await repository.setFollowedCreators(ids: added, replacingExisting: false)
            }
            if !removed.isEmpty {
                try await repository.unfollow(creatorIds: removed)
            }
            initialSelection = selection
            return true
        } catch {
            logger.warning("save followed creators failed: \(error)")
            return false
        }
    }

    // MARK: Loading

    /// `_initialFavouriteIds` — every followed creator, so the grid can show
    /// them checked before the user touches anything.
    private func loadInitialSelection() async {
        var ids: Set<String> = []
        var next = 1
        while next < 50 {
            guard let result = try? await favourites.fetchFavouriteCreators(type: songType, page: next) else { break }
            ids.formUnion(result.items.compactMap(\.creatorId))
            guard result.hasMore else { break }
            next += 1
        }
        initialSelection = ids
        selection = ids
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        do {
            let result = try await repository.fetchAllCreators(page: page + 1)
            creators.append(contentsOf: result.items)
            page = result.page
            hasMore = result.hasMore
        } catch {
            logger.warning("all creators page load failed: \(error)")
            if page == 0 { hasMore = false }
        }
        isLoading = false
        hasLoadedOnce = true
    }
}
