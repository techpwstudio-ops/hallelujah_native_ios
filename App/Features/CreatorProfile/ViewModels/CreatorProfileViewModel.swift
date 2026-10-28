import Foundation
import Observation

/// One of `CreatorSongsPage._setupTabs`'s (`lib/views/library/creator_songs_page.dart`)
/// four tabs, shown only when its matching count is > 0, same as Dart.
enum CreatorProfileTab: Hashable, Sendable {
    case songs(HomeContentType)
    case playlists(HomeContentType)

    var title: String {
        switch self {
        case .songs(.music): "Songs"
        case .songs(.episode): "Podcasts"
        case .playlists(.music): "Albums"
        case .playlists(.episode): "Seasons"
        case .songs, .playlists: ""
        }
    }
}

/// One tab's paged list state — songs and playlists share the same shape
/// (page cursor, in-flight flag, `hasMore`), so one generic struct covers
/// both rather than two near-identical hand-rolled state types.
struct CreatorContentPage<Item: Sendable>: Sendable {
    var items: [Item] = []
    var page = 0
    var hasMore = true
    var isLoading = false
    var loadedOnce = false
}

/// `CreatorSongsPage` (`lib/views/library/creator_songs_page.dart`) — a
/// creator's header (image, name, follower count, follow button) plus their
/// paginated songs/albums/podcasts/seasons tabs (T30).
///
/// Dart's own screen fetches the creator from the API and writes it into
/// Realm on every load (`_fetchCreatorFromApi`), so any other screen reading
/// the same Realm row sees the update — the "reflected in Library" half of
/// this task's Done criterion. This app has no local content cache: a
/// `Creator` fetched or mutated here is only ever held by this view model's
/// own `creator` property, so there's nothing to desync — a future Library
/// screen (T44/T45) calling the same `CreatorRepository` gets the same
/// server-authoritative state directly, with no separate cache to keep in
/// sync in the first place.
@MainActor
@Observable
final class CreatorProfileViewModel {
    private(set) var creator: Creator?
    private(set) var isLoadingCreator = false
    private(set) var loadError: String?
    private(set) var isTogglingFollow = false
    /// Toast text when a follow toggle failed (and was put back).
    private(set) var followError: String?

    private(set) var tabs: [CreatorProfileTab] = []
    var selectedTab: CreatorProfileTab?

    private var songPages: [HomeContentType: CreatorContentPage<Song>] = [:]
    private var playlistPages: [HomeContentType: CreatorContentPage<Playlist>] = [:]

    let creatorId: String
    private let repository: any CreatorRepository
    private let logger = AppLogger(category: .content)

    /// `container.resolve()` — same DI convention as `HomeFeedViewModel`/
    /// `AccountSetupViewModel`'s own `init(container: DependencyContainer = .current)`.
    init(creatorId: String, container: DependencyContainer = .current) {
        self.creatorId = creatorId
        self.repository = container.resolve()
    }

    func onAppear() async {
        guard creator == nil, !isLoadingCreator else { return }
        await loadCreator()
    }

    func loadCreator() async {
        isLoadingCreator = true
        loadError = nil
        do {
            let fetched = try await repository.fetchCreator(id: creatorId)
            creator = fetched
            configureTabs(for: fetched)
        } catch {
            logger.warning("creator detail load failed: \(error)")
            loadError = String(localized: "Something went wrong")
        }
        isLoadingCreator = false
    }

    /// `_setupTabs` (`creator_songs_page.dart`): Songs → Albums → Podcasts →
    /// Seasons, each included only when its count is positive.
    private func configureTabs(for creator: Creator) {
        var built: [CreatorProfileTab] = []
        if (creator.musicCount ?? 0) > 0 { built.append(.songs(.music)) }
        if (creator.albumsCount ?? 0) > 0 { built.append(.playlists(.music)) }
        if (creator.episodeCount ?? 0) > 0 { built.append(.songs(.episode)) }
        if (creator.seasonsCount ?? 0) > 0 { built.append(.playlists(.episode)) }
        tabs = built
        if selectedTab.map({ !built.contains($0) }) ?? true {
            selectedTab = built.first
        }
    }

    // MARK: - Follow

    /// The follow state shown: the shared store's (a toggle on any other
    /// screen) over the fetched flag.
    var isFollowing: Bool {
        CreatorFollowStore.shared.isFollowing(creator?.creatorId ?? creatorId, fallback: creator?.isFollowing)
    }

    /// The fetched count, moved by one when the follow state changed since
    /// the fetch (here or on another screen).
    var followersCount: Int? {
        guard let count = creator?.followersCount else { return nil }
        let fetched = creator?.isFollowing == true
        if isFollowing == fetched { return count }
        return isFollowing ? count + 1 : max(count - 1, 0)
    }

    func toggleFollow() async {
        guard let creator, !isTogglingFollow else { return }
        // The fetched creator's id, else the one the page was opened with.
        let id = creator.creatorId ?? creatorId
        isTogglingFollow = true
        defer { isTogglingFollow = false }

        let store = CreatorFollowStore.shared
        let wasFollowing = isFollowing
        let previousState = store.state(for: id)
        // Optimistic, like `CreatorFollowButton`'s instant toggle.
        store.set(!wasFollowing, for: id)
        do {
            if wasFollowing {
                try await repository.unfollow(creatorId: id)
            } else {
                try await repository.follow(creatorId: id)
            }
        } catch {
            logger.warning("follow toggle for \(id) failed: \(error)")
            store.set(previousState, for: id)
            followError = String(localized: "Internet error, please check your internet")
        }
    }

    func clearFollowError() {
        followError = nil
    }

    // MARK: - Songs paging

    func songs(for type: HomeContentType) -> [Song] {
        songPages[type]?.items ?? []
    }

    func hasLoadedSongs(for type: HomeContentType) -> Bool {
        songPages[type]?.loadedOnce ?? false
    }

    func hasLoadedPlaylists(for type: HomeContentType) -> Bool {
        playlistPages[type]?.loadedOnce ?? false
    }

    func isLoadingSongs(for type: HomeContentType) -> Bool {
        songPages[type]?.isLoading ?? false
    }

    /// Called once when a tab is first selected — `CreatorSongsSliver`'s
    /// `initState` load-or-refresh, minus the "refresh in background" half:
    /// there's no local cache here for a refresh to reconcile against.
    func loadSongsIfNeeded(type: HomeContentType) async {
        guard !(songPages[type]?.loadedOnce ?? false) else { return }
        await loadMoreSongs(type: type)
    }

    /// `CreatorSongsSliver`'s sentinel-item pagination trigger, translated to
    /// "the row currently on screen is near the end of what's loaded."
    func loadMoreSongsIfNeeded(type: HomeContentType, currentItem: Song) async {
        let items = songs(for: type)
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= items.count - 3 else { return }
        await loadMoreSongs(type: type)
    }

    func loadMoreSongs(type: HomeContentType) async {
        var page = songPages[type] ?? CreatorContentPage()
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        songPages[type] = page

        do {
            let result = try await repository.fetchSongs(creatorId: creatorId, type: type, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
            page.loadedOnce = true
        } catch {
            logger.warning("creator songs page load failed: \(error)")
            page.loadedOnce = true
        }
        page.isLoading = false
        songPages[type] = page
    }

    // MARK: - Playlists paging (albums / seasons)

    func playlists(for type: HomeContentType) -> [Playlist] {
        playlistPages[type]?.items ?? []
    }

    func isLoadingPlaylists(for type: HomeContentType) -> Bool {
        playlistPages[type]?.isLoading ?? false
    }

    func loadPlaylistsIfNeeded(type: HomeContentType) async {
        guard !(playlistPages[type]?.loadedOnce ?? false) else { return }
        await loadMorePlaylists(type: type)
    }

    func loadMorePlaylistsIfNeeded(type: HomeContentType, currentItem: Playlist) async {
        let items = playlists(for: type)
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= items.count - 3 else { return }
        await loadMorePlaylists(type: type)
    }

    func loadMorePlaylists(type: HomeContentType) async {
        var page = playlistPages[type] ?? CreatorContentPage()
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        playlistPages[type] = page

        do {
            let result = try await repository.fetchPlaylists(creatorId: creatorId, type: type, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
            page.loadedOnce = true
        } catch {
            logger.warning("creator playlists page load failed: \(error)")
            page.loadedOnce = true
        }
        page.isLoading = false
        playlistPages[type] = page
    }
}
