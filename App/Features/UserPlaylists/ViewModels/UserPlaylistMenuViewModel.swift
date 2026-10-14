import Foundation
import Observation

/// Data side of `showUserPlaylistMenu` (`lib/sheets/custom_playlist.dart`).
/// Decides what the row's "more" sheet offers (owner-only rows) and performs
/// "Add to queue" for the whole playlist. Also hosts the share,
/// public/private toggle and add-to/remove-from-library rows through
/// `actions`.
@MainActor
@Observable
final class UserPlaylistMenuViewModel {
    let playlistID: String
    let title: String
    private(set) var isOwner = false
    private(set) var isBusy = false
    let actions: UserPlaylistActionsViewModel
    private(set) var isLoaded = false

    private let repository: any UserPlaylistRepository
    private let currentUserStore: CurrentUserStore
    private let queueController: QueueController
    private let logger = AppLogger(category: .content)

    init(playlistID: String, title: String, container: DependencyContainer = .current) {
        self.playlistID = playlistID
        self.title = title
        repository = container.resolve()
        currentUserStore = container.resolve()
        queueController = container.resolve()
        actions = UserPlaylistActionsViewModel(playlistID: playlistID, container: container)
    }

    func load() async {
        defer { isLoaded = true }
        guard let playlist = try? await repository.fetchPlaylist(id: playlistID) else { return }
        isOwner = playlist.isOwned(by: await currentUserStore.user?.id)
        actions.setVisibility(playlist.visibility)
        if !isOwner { await actions.loadFollowState() }
    }

    /// `AddSourceToQueueEvent(QueueSource(userPlaylist, id, title))`.
    func addToQueue() async -> String {
        isBusy = true
        defer { isBusy = false }
        var songs: [Song] = []
        var page = 1
        while page <= 20 {
            guard let result = try? await repository.fetchSongs(playlistID: playlistID, page: page) else { break }
            songs.append(contentsOf: result.songs.items)
            if !result.songs.hasMore { break }
            page += 1
        }
        guard !songs.isEmpty else { return "Nothing to add" }
        let source = QueueAttribution(playerType: .userPlaylist, id: playlistID, title: title.isEmpty ? "this playlist" : title)
        let added = await queueController.addToQueue(songs, source: source)
        return added > 0 ? "Added to queue" : "Already in your queue"
    }

    func delete() async -> Bool {
        do {
            try await repository.deletePlaylist(id: playlistID)
            return true
        } catch {
            logger.warning("delete playlist \(playlistID) failed: \(error)")
            return false
        }
    }
}
