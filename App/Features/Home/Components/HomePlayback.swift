import SwiftUI
import Observation

/// Playback glue shared by every Home card and list row: the native stand-in
/// for `playerBloc.add(PlaySongEvent(playerType:, playerId:, songId:, songs:))`
/// and `PlayPauseIcon`'s `BlocBuilder<PlayerBloc, …>`.
///
/// One instance resolves the shared `QueueController`/`AudioEngine` once, so a
/// rail of fifty cards does not each resolve their own. Both are `@Observable`,
/// so a view that reads `isPlaying(...)` inside its `body` re-renders when
/// playback changes.
@MainActor
final class HomePlayback {
    static let shared = HomePlayback()

    let queueController: QueueController
    let audioEngine: AudioEngine

    private init() {
        queueController = DependencyContainer.current.resolve()
        audioEngine = DependencyContainer.current.resolve()
    }

    /// `getPlayerId(PlayerType.home, uiId)`.
    static func homeAttribution(uiId: String?, title: String = "") -> QueueAttribution {
        QueueAttribution(playerType: .home, id: uiId, title: title)
    }

    // MARK: State

    func isCurrent(songID: String) -> Bool {
        audioEngine.currentSong?.id == songID
    }

    func isPlaying(songID: String) -> Bool {
        isCurrent(songID: songID) && audioEngine.status == .playing
    }

    /// `PlayPauseIcon`: shows pause while the song is current AND playing or
    /// still loading (`audioProcessingState != ready`).
    func showsPause(songID: String) -> Bool {
        guard isCurrent(songID: songID) else { return false }
        switch audioEngine.status {
        case .playing, .loading: return true
        default: return false
        }
    }

    func isQueueActive(_ source: QueueAttribution) -> Bool {
        queueController.queue?.source.playerID == source.playerID
    }

    func isPlaying(source: QueueAttribution) -> Bool {
        isQueueActive(source) && audioEngine.status == .playing
    }

    // MARK: Actions

    func togglePlayPause() {
        if audioEngine.status == .playing {
            audioEngine.pause()
        } else {
            audioEngine.resume()
        }
    }

    /// `PlaySongEvent` from a tapped card/row. Tapping the song already
    /// playing in THIS queue toggles play/pause in place (no restart, no
    /// navigation) — `PlayerBloc._onPlaySong`'s early return; any other tap
    /// starts the list at that song and opens the full player.
    func play(
        song: Song,
        in songs: [Song],
        source: QueueAttribution,
        coordinator: AppNavigationCoordinator
    ) {
        if isQueueActive(source), queueController.queue?.currentSong?.id == song.id {
            togglePlayPause()
            return
        }
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        let controller = queueController
        Task {
            await controller.play(songs: songs, startIndex: index, source: source)
            coordinator.presentPlayer()
        }
    }

    /// The header Play/Pause button: toggles if this container is the active
    /// queue, otherwise starts it from the first song.
    func playFirst(
        of songs: [Song],
        source: QueueAttribution,
        coordinator: AppNavigationCoordinator
    ) {
        guard !songs.isEmpty else { return }
        if isQueueActive(source) {
            togglePlayPause()
            return
        }
        let controller = queueController
        Task {
            await controller.play(songs: songs, startIndex: 0, source: source)
            coordinator.presentPlayer()
        }
    }
}

/// `PlayPauseIcon` — a ring (1.25pt white border) around a play/pause glyph,
/// sized by `size` (28 on the episode cards).
struct HomePlayPauseIcon: View {
    let songID: String
    var size: CGFloat = 28

    var body: some View {
        let showsPause = HomePlayback.shared.showsPause(songID: songID)
        ZStack {
            Circle().strokeBorder(Color.white, lineWidth: 1.25)
            Image(systemName: showsPause ? "pause.fill" : "play.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: showsPause)
    }
}

/// `PlayPauseIconFilled` — the 48pt white disc with a dark glyph used by the
/// playlist/see-all headers.
struct HomePlayPauseFilled: View {
    let source: QueueAttribution
    var diameter: CGFloat = 48

    var body: some View {
        let isPlaying = HomePlayback.shared.isPlaying(source: source)
        ZStack {
            Circle().fill(Color.white)
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.black)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}
