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
            loadError = "Something went wrong"
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

    func toggleFollow() async {
        guard let creator, !isTogglingFollow else { return }
        isTogglingFollow = true

        let wasFollowing = creator.isFollowing == true
        // Optimistic flip, mirrors `CreatorFollowButton`'s instant toggle
        // (`lib/widgets/player/creator_follow_button.dart`) before the
        // network call resolves.
        self.creator = Self.applyingFollow(to: creator, isFollowing: !wasFollowing)

        do {
            let updated = wasFollowing
                ? try await repository.unfollow(creatorId: creator.id)
                : try await repository.follow(creatorId: creator.id)
            self.creator = updated
        } catch {
            logger.warning("follow toggle failed: \(error)")
            self.creator = creator // revert to the pre-toggle snapshot
        }
        isTogglingFollow = false
    }

    private static func applyingFollow(to creator: Creator, isFollowing: Bool) -> Creator {
        Creator(
            creatorId: creator.creatorId,
            name: creator.name,
            displayName: creator.displayName,
            image: creator.image,
            imageVariants: creator.imageVariants,
            bio: creator.bio,
            email: creator.email,
            mobile: creator.mobile,
            username: creator.username,
            link: creator.link,
            band: creator.band,
            isActive: creator.isActive,
            createdAt: creator.createdAt,
            updatedAt: creator.updatedAt,
            followersCount: creator.followersCount.map { isFollowing ? $0 + 1 : max($0 - 1, 0) },
            songsCount: creator.songsCount,
            episodeCount: creator.episodeCount,
            musicCount: creator.musicCount,
            playlistsCount: creator.playlistsCount,
            albumsCount: creator.albumsCount,
            seasonsCount: creator.seasonsCount,
            isFollowing: isFollowing
        )
    }

    // MARK: - Songs paging

    func songs(for type: HomeContentType) -> [Song] {
        songPages[type]?.items ?? []
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
        }
        page.isLoading = false
        playlistPages[type] = page
    }
}
