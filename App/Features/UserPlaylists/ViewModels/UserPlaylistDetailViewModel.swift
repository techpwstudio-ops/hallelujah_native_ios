import Foundation

/// T45 — a signed-in user's own playlist: header, paginated songs, and
/// owner-only admin actions (add/remove songs, rename, delete). Ports
/// `UserPlaylistSongs` (`lib/views/library/user_playlist_songs.dart`).
///
/// `LoadState` mirrors `PlaylistDetailViewModel`'s own enum shape, widened
/// to carry the playlist header alongside the song page: unlike
/// `PlaylistDetailViewModel`, which is handed an already-loaded `Playlist`
/// via init, this screen only ever has an id (`AppRoute.userPlaylistSongs`)
/// and fetches both together through `UserPlaylistSongsPage` — one round
/// trip, no separate `fetchPlaylist(id:)` call.
@Observable
@MainActor
final class UserPlaylistDetailViewModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded(playlist: UserPlaylist, songs: Paginated<Song>)
        case empty(playlist: UserPlaylist)
        case failed
    }

    let playlistID: String?
    private(set) var state: LoadState = .loading
    private(set) var isLoadingMore = false
    private(set) var isOwner = false

    private let repository: any UserPlaylistRepository
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .content)
    private var loadTask: Task<Void, Never>?

    init(playlistID: String?, container: DependencyContainer = .current) {
        self.playlistID = playlistID
        repository = container.resolve()
        currentUserStore = container.resolve()
    }

    func loadIfNeeded() async {
        guard case .loading = state, loadTask == nil else { return }
        await load(page: 1)
    }

    func refresh() async {
        await load(page: 1)
    }

    func loadMore() {
        guard let playlistID, case .loaded(let playlist, let page) = state, page.hasMore, loadTask == nil else { return }
        isLoadingMore = true
        loadTask = Task {
            defer {
                isLoadingMore = false
                loadTask = nil
            }
            do {
                let next = try await repository.fetchSongs(playlistID: playlistID, page: page.page + 1)
                state = .loaded(playlist: playlist, songs: Paginated(
                    items: page.items + next.songs.items, page: next.songs.page, perPage: next.songs.perPage,
                    total: next.songs.total, totalPages: next.songs.totalPages, hasMore: next.songs.hasMore
                ))
            } catch {
                logger.warning("playlist \(playlistID) page \(page.page + 1) failed: \(error)")
                // Leaves the already-loaded rows on screen; the user's own
                // scroll-triggered retry (calling `loadMore()` again) can
                // try once more.
            }
        }
    }

    /// `detachSongs` plus a full reload — `UserPlaylistRepository`'s own doc
    /// comment is why this doesn't try to reconcile a mutated playlist in
    /// place instead.
    func removeSong(id: String) async {
        guard let playlistID else { return }
        do {
            try await repository.detachSongs(playlistID: playlistID, songIDs: [id])
            await refresh()
        } catch {
            logger.warning("remove song \(id) from playlist \(playlistID) failed: \(error)")
        }
    }

    /// Whether the delete succeeded, so the view only pops on success.
    func deletePlaylist() async -> Bool {
        guard let playlistID else { return false }
        do {
            try await repository.deletePlaylist(id: playlistID)
            return true
        } catch {
            logger.warning("delete playlist \(playlistID) failed: \(error)")
            return false
        }
    }

    private func load(page: Int) async {
        guard let playlistID else {
            // No id to fetch with — defensive, matches
            // `GenreSongsViewModel.loadMoreSongs()`'s identical nil-id
            // guard. `.failed` rather than spinning forever: unlike that
            // view model's bare item list, `LoadState` here has no "loaded,
            // no playlist" case to fall into, so this is the closest
            // equivalent "stop and let the view show a retry" state.
            state = .failed
            return
        }
        state = .loading
        loadTask = Task {
            defer { loadTask = nil }
            do {
                let result = try await repository.fetchSongs(playlistID: playlistID, page: page)
                isOwner = result.playlist.isOwned(by: await currentUserStore.user?.id)
                state = result.songs.items.isEmpty
                    ? .empty(playlist: result.playlist)
                    : .loaded(playlist: result.playlist, songs: result.songs)
            } catch {
                logger.warning("playlist \(playlistID) page \(page) failed: \(error)")
                state = .failed
            }
        }
        await loadTask?.value
    }
}
