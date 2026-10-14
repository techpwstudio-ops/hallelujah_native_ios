import Foundation

/// Backs `SongMenuSheet` — the native `showSongMenu` (`lib/sheets/song/
/// song_menu_sheet.dart`) and the sheets it opens (credits, report, add to
/// playlist). Every action returns a `SongMenuOutcome` rather than touching
/// navigation or toasts itself, so the view decides how to present the result
/// and this type stays testable.
@MainActor
@Observable
final class SongMenuViewModel {
    enum Page: Equatable {
        case menu
        case share
        case credits
        case report
        case addToPlaylist
    }

    enum Loadable<Value: Equatable>: Equatable {
        case idle
        case loading
        case loaded(Value)
        case failed
    }

    private(set) var song: Song
    let userPlaylistID: String?
    private(set) var downloadState: DownloadState?
    var page: Page = .menu

    private(set) var credits: Loadable<[SongCreditGroup]> = .idle
    private(set) var playlists: Loadable<[UserPlaylist]> = .idle
    private(set) var isBusy = false

    private let favouriteRepository: any FavouriteRepository
    private let songRepository: any SongRepository
    private let userPlaylistRepository: any UserPlaylistRepository
    private let downloadEngine: DownloadEngine
    private let queueController: QueueController
    private let engine: AudioEngine
    private let premiumGate: PremiumGate
    private let keyValueStore: any KeyValueStoring
    private let logger = AppLogger(category: .content)

    init(song: Song, userPlaylistID: String? = nil, container: DependencyContainer = .current) {
        self.song = song
        self.userPlaylistID = userPlaylistID
        favouriteRepository = container.resolve()
        songRepository = container.resolve()
        userPlaylistRepository = container.resolve()
        downloadEngine = container.resolve()
        queueController = container.resolve()
        engine = container.resolve()
        premiumGate = container.resolve()
        keyValueStore = container.resolve()
        downloadState = downloadEngine.tasks[song.id]?.state
    }

    var isEpisode: Bool { song.isEpisode }
    var isInUserPlaylist: Bool { userPlaylistID != nil }

    /// Title of the download row, ported from the `switch` over
    /// `DownloadTaskStatus` in `song_menu_sheet.dart`.
    var downloadTitle: String {
        switch downloadState {
        case nil: isEpisode ? "Download Episode" : "Download Music"
        case .completed, .queued: "Remove From Downloads"
        case .downloading: "Cancel Downloading"
        case .failed: "Retry Downloading"
        case .paused: "Resume Downloading"
        }
    }

    // MARK: - Actions

    func toggleFavourite() async -> SongMenuOutcome {
        let target = !song.isFavorited
        song = song.withFavorited(target)
        engine.setCurrentSongFavorited(target, songId: song.id)
        do {
            try await favouriteRepository.toggleSongFavorite(songId: song.id, isFavorited: target)
            return .message(target ? "Added to favorites" : "Removed from favorites")
        } catch {
            song = song.withFavorited(!target)
            engine.setCurrentSongFavorited(!target, songId: song.id)
            return .message("Network error")
        }
    }

    /// `showQueueSheet(songId:)`: a song not yet queued is appended; one that
    /// is already queued opens the queue instead.
    func addToQueue() async -> SongMenuOutcome {
        let source = QueueAttribution(playerType: .home, id: nil, title: "")
        let added = await queueController.addToQueue(song, source: queueController.queue?.source ?? source)
        return added ? .message("Added to queue") : .openQueue
    }

    func removeFromPlaylist() async -> SongMenuOutcome {
        guard let userPlaylistID else { return .dismiss }
        do {
            try await userPlaylistRepository.detachSongs(playlistID: userPlaylistID, songIDs: [song.id])
            return .message("Removed from playlist")
        } catch {
            logger.warning("remove from playlist failed: \(error)")
            return .message("Network error")
        }
    }

    /// The artist to open: from the list payload when it has one, else from
    /// the detail response (Dart fetches the song "so we route with a valid
    /// artistId rather than the local creatorId").
    func resolveArtistID() async -> String? {
        if let id = Self.artistID(of: song) { return id }
        guard let detailed = try? await songRepository.fetchSong(id: song.id) else { return nil }
        return Self.artistID(of: detailed)
    }

    func download() async -> SongMenuOutcome {
        guard await premiumGate.allows(.downloads) else { return .requiresPremium }
        switch downloadEngine.tasks[song.id]?.state {
        case nil:
            let quality = await AudioQualitySelector.live(keyValueStore: keyValueStore).targetQuality()
            await downloadEngine.enqueue(song: song, quality: quality)
        case .completed, .queued:
            downloadEngine.deleteDownload(songID: song.id)
        case .downloading:
            downloadEngine.cancel(songID: song.id)
        case .failed:
            await downloadEngine.retry(songID: song.id)
        case .paused:
            downloadEngine.resume(songID: song.id)
        }
        downloadState = downloadEngine.tasks[song.id]?.state
        return .dismiss
    }

    func requestSleepTimer() async -> SongMenuOutcome {
        await premiumGate.allows(.sleepTimer) ? .openSleepTimer : .requiresPremium
    }

    func stopPlayback() -> SongMenuOutcome {
        queueController.clear()
        return .stopped
    }

    // MARK: - Credits

    func loadCredits() async {
        credits = .loading
        do {
            let detailed = try await songRepository.fetchSong(id: song.id)
            credits = .loaded((detailed.songCredits ?? []).groupedByCategory())
        } catch {
            credits = .failed
        }
    }

    // MARK: - Add to playlist

    func loadPlaylists() async {
        playlists = .loading
        do {
            playlists = .loaded(try await userPlaylistRepository.fetchPlaylists(page: 1).items)
        } catch {
            playlists = .failed
        }
    }

    func add(to playlist: UserPlaylist) async -> SongMenuOutcome {
        isBusy = true
        defer { isBusy = false }
        do {
            try await userPlaylistRepository.attachSongs(playlistID: playlist.id, songIDs: [song.id])
            return .message("Added to \(playlist.title)")
        } catch {
            return .notice("Network error")
        }
    }

    // MARK: - Report

    /// `ReportedSongsBloc.reportSong`: a blank reason is refused locally; on
    /// success playback stops (the server now hides the song from this
    /// listener) and the player closes.
    func report(reason: String) async -> SongMenuOutcome {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notice("Please enter a reason and try again") }
        isBusy = true
        defer { isBusy = false }
        do {
            try await songRepository.reportSong(id: song.id, message: trimmed)
            queueController.clear()
            return .reported
        } catch SongRepositoryError.rejected(let message) {
            return .notice(message)
        } catch {
            return .notice("Network error")
        }
    }

    nonisolated static func artistID(of song: Song) -> String? {
        song.creator?.creatorId ?? song.songPrimaryArtists.compactMap(\.creatorId).first
    }
}

/// What a menu action asks its host view to do next.
enum SongMenuOutcome: Equatable {
    /// Toast, then close the sheet (the action succeeded or is finished).
    case message(String)
    /// Toast and keep the sheet open (validation or a retryable failure).
    case notice(String)
    case dismiss
    case openQueue
    case openSleepTimer
    case requiresPremium
    case stopped
    case reported
    case goToArtist(String)
}
