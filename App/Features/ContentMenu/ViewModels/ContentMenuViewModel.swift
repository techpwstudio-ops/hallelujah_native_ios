import Foundation

/// A whole container the overflow menu can act on — a company playlist, an
/// album/season, or an artist (`showContentMenu`/`showCreatorMenu`,
/// `lib/sheets/playlist/content_menu_sheet.dart`, `creator_menu_sheet.dart`).
enum ContentMenuTarget: Identifiable, Equatable, Sendable {
    case playlist(Playlist)
    case creator(Creator)

    var id: String {
        switch self {
        case .playlist(let playlist): "playlist-\(playlist.id)"
        case .creator(let creator): "creator-\(creator.id)"
        }
    }

    var title: String {
        switch self {
        case .playlist(let playlist): playlist.title
        case .creator(let creator): creator.displayName ?? creator.name ?? ""
        }
    }

    /// Only a company playlist and an artist have a share endpoint behind
    /// them — an album can never show a button that would 404, because the
    /// row is derived from what the target *is*.
    var shareTarget: ShareTarget? {
        switch self {
        case .playlist(let playlist): playlist.owner == .company ? .companyPlaylist(id: playlist.id) : nil
        case .creator(let creator): creator.creatorId.map { .creator(id: $0) }
        }
    }

    var libraryItem: (type: LibraryItemType, id: String)? {
        switch self {
        case .playlist(let playlist): (playlist.libraryItemType, playlist.id)
        case .creator: nil
        }
    }

    var queueSource: QueueAttribution {
        switch self {
        case .playlist(let playlist):
            QueueAttribution(
                playerType: playlist.owner == .company ? .companyPlaylist : (playlist.isSeason ? .season : .album),
                id: playlist.id,
                title: playlist.title
            )
        case .creator(let creator):
            QueueAttribution(playerType: .creator, id: creator.creatorId, title: creator.name ?? "this artist")
        }
    }
}

/// What a content-menu action asks its host to do next.
enum ContentMenuOutcome: Equatable {
    case message(String)
    case dismiss
}

/// Backs `ContentMenuSheet`. Like `SongMenuViewModel`, actions return an
/// outcome and leave toasts/dismissal to the view.
@MainActor
@Observable
final class ContentMenuViewModel {
    let target: ContentMenuTarget
    private(set) var isBusy = false
    private(set) var isFollowing: Bool

    private let playlists: any PlaylistRepository
    private let creators: any CreatorRepository
    private let queueController: QueueController
    private let logger = AppLogger(category: .content)

    /// Same ceiling as the CarPlay lists: enough to fill a queue, not a crawl
    /// of a huge catalogue on one tap.
    private static let maxQueuedSongs = 100

    init(target: ContentMenuTarget, container: DependencyContainer = .current) {
        self.target = target
        playlists = container.resolve()
        creators = container.resolve()
        queueController = container.resolve()
        if case .creator(let creator) = target {
            isFollowing = creator.isFollowing == true
        } else {
            isFollowing = false
        }
    }

    var canQueue: Bool { target.queueSource.playerType.isQueueable }

    func addToQueue() async -> ContentMenuOutcome {
        isBusy = true
        defer { isBusy = false }
        let songs = await fetchSongs()
        guard !songs.isEmpty else { return .message("Nothing to add") }
        let added = await queueController.addToQueue(songs, source: target.queueSource)
        return .message(added > 0 ? "Added to queue" : "Already in your queue")
    }

    /// Follow / unfollow an artist — the creator menu's "Add to library".
    func toggleFollow() async -> ContentMenuOutcome {
        guard case .creator(let creator) = target, let id = creator.creatorId else { return .dismiss }
        isBusy = true
        defer { isBusy = false }
        do {
            if isFollowing {
                try await creators.unfollow(creatorId: id)
            } else {
                try await creators.follow(creatorId: id)
            }
            isFollowing.toggle()
            return .message(isFollowing ? "Added to library" : "Removed from library")
        } catch {
            logger.warning("follow toggle failed: \(error)")
            return .message("Network error")
        }
    }

    private func fetchSongs() async -> [Song] {
        var songs: [Song] = []
        var page = 1
        while songs.count < Self.maxQueuedSongs {
            let result: Paginated<Song>?
            switch target {
            case .playlist(let playlist):
                result = try? await playlists.fetchSongs(playlistId: playlist.id, owner: playlist.owner, page: page)
            case .creator(let creator):
                guard let id = creator.creatorId else { return songs }
                result = try? await creators.fetchSongs(creatorId: id, type: .all, page: page)
            }
            guard let result else { break }
            songs += result.items
            guard result.hasMore, !result.items.isEmpty else { break }
            page += 1
        }
        return Array(songs.prefix(Self.maxQueuedSongs))
    }
}
