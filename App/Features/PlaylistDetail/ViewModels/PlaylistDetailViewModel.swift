import Foundation
import Observation

/// One playlist's own song list — T29's "album songs"/"company playlist
/// songs" screens, unified into one screen the same way `Playlist` already
/// unifies `CompanyPlaylist`/`CreatorPlaylist` (T27). Takes the full
/// `Playlist` via init rather than just an id: unlike Dart, which reads a
/// company playlist's header (title/image/songsCount) from its local Realm
/// cache (`CompanyPlaylistSongsPage`) and only threads a bare id through
/// navigation, this app has no native local content cache, so the header
/// has to travel with the navigation call instead — matching how
/// `PlaylistSongPage` (the creator-playlist screen) already does it, a
/// pattern this screen extends to both owners rather than inventing a
/// separate "fetch playlist detail" round trip just for the company case.
@Observable
@MainActor
final class PlaylistDetailViewModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded(Paginated<Song>)
        case empty
        case failed
    }

    let playlist: Playlist
    private(set) var state: LoadState = .loading
    private(set) var isLoadingMore = false

    private let repository: any PlaylistRepository
    private let logger = AppLogger(category: .content)
    private var loadTask: Task<Void, Never>?

    init(playlist: Playlist, container: DependencyContainer = .current) {
        self.playlist = playlist
        repository = container.resolve()
    }

    func loadIfNeeded() async {
        guard case .loading = state, loadTask == nil else { return }
        await load(page: 1)
    }

    func refresh() async {
        await load(page: 1)
    }

    func loadMore() {
        guard case .loaded(let page) = state, page.hasMore, loadTask == nil else { return }
        isLoadingMore = true
        loadTask = Task {
            defer {
                isLoadingMore = false
                loadTask = nil
            }
            do {
                let next = try await repository.fetchSongs(
                    playlistId: playlist.id, owner: playlist.owner, page: page.page + 1
                )
                state = .loaded(Paginated(
                    items: page.items + next.items, page: next.page, perPage: next.perPage,
                    total: next.total, totalPages: next.totalPages, hasMore: next.hasMore
                ))
            } catch {
                logger.warning("playlist \(self.playlist.id) page \(page.page + 1) failed: \(error)")
                // Leaves the already-loaded rows on screen; the user's own
                // scroll-triggered retry (calling `loadMore()` again) can
                // try once more.
            }
        }
    }

    private func load(page: Int) async {
        state = .loading
        loadTask = Task {
            defer { loadTask = nil }
            do {
                let result = try await repository.fetchSongs(playlistId: playlist.id, owner: playlist.owner, page: page)
                state = result.items.isEmpty ? .empty : .loaded(result)
            } catch {
                logger.warning("playlist \(self.playlist.id) page \(page) failed: \(error)")
                state = .failed
            }
        }
        await loadTask?.value
    }
}
