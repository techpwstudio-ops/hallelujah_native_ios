import SwiftUI

/// Ports `DownloadsPage` (`lib/views/library/downloads.dart`): a 220pt
/// `#4E00F6 @ 67% -> black` gradient header ("Downloads" 26pt bold, Shuffle +
/// Play, "<n> Songs · <m> Podcasts" in white70), a Music / Podcast toggle
/// (`SongTypeTopNavigationButton`, 16pt gap, 16pt inset), then the downloaded
/// `SongListItem` rows separated by 12pt, or "Nothing in Downloads".
///
/// Native-only additions the Dart screen has no equivalent for (the engine
/// models real in-flight states): a 2pt progress bar under a row that is
/// queued/downloading/paused, an 8pt bold red "Downloading Failed" label
/// (`DownloadProgressWidget`'s exact styles), and pause/resume/cancel/retry
/// buttons trailing such a row. `type` is accepted for route parity; the
/// toggle starts on Music like Dart's `songType` default.
struct DownloadsView: View {
    let type: String

    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var isEpisodes = false

    @Environment(AppNavigationCoordinator.self) private var coordinator

    /// `ColorTheme.downloadsBgTopColor` (0xAB4E00F6).
    private static let gradientTop = Color(red: 0x4E / 255, green: 0x00 / 255, blue: 0xF6 / 255).opacity(0xAB / 255)
    private static let attribution = QueueAttribution(playerType: .download, id: "downloaded", title: "Downloads")

    // MARK: - Data

    private var allTasks: [DownloadTask] {
        downloadEngine.tasks.values.sorted { lhs, rhs in
            let lhsRank = sortRank(for: lhs.state)
            let rhsRank = sortRank(for: rhs.state)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func sortRank(for state: DownloadState) -> Int {
        switch state {
        case .downloading, .queued, .paused: 0
        case .completed: 1
        case .failed: 2
        }
    }

    private func isEpisode(_ task: DownloadTask) -> Bool { task.songType == "episode" }

    private var visibleTasks: [DownloadTask] {
        allTasks.filter { isEpisode($0) == isEpisodes }
    }

    private var completedVisibleSongs: [Song] {
        visibleTasks.filter { $0.state == .completed }.map(Song.makeDownloadedSnapshot)
    }

    private var songCount: Int { allTasks.filter { $0.state == .completed && !isEpisode($0) }.count }
    private var episodeCount: Int { allTasks.filter { $0.state == .completed && isEpisode($0) }.count }

    // MARK: - Body

    var body: some View {
        ParityGradientHeader(
            top: Self.gradientTop,
            title: "Downloads",
            subtitle: "\(songCount) Songs \u{00B7} \(episodeCount) Podcasts",
            isShuffled: queueController.isShuffled,
            isPlaying: isPlaying,
            onShuffle: { Task { await queueController.toggleShuffle() } },
            onPlay: { togglePlayback() },
            extra: { typeToggle },
            content: { list }
        )
        .background(Color.black)
    }

    private var typeToggle: some View {
        HStack(spacing: Dimens.horizontalSpacing) {
            ParityTypeButton(title: "Music", isSelected: !isEpisodes) { isEpisodes = false }
            ParityTypeButton(title: "Podcast", isSelected: isEpisodes) { isEpisodes = true }
        }
        .padding(.horizontal, Dimens.screenPaddingAll + 8)
    }

    @ViewBuilder
    private var list: some View {
        let tasks = visibleTasks
        if tasks.isEmpty {
            Text("Nothing in Downloads")
                .font(.custom(Typography.fontFamily, size: 14))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Dimens.verticalSpacing) {
                    ForEach(tasks) { task in
                        row(for: task)
                    }
                    Color.clear.frame(height: 16)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Row

    private func row(for task: DownloadTask) -> some View {
        let song = Song.makeDownloadedSnapshot(task)
        return HStack(spacing: 0) {
            CreatorSongRow(
                song: song,
                showsMenu: task.state == .completed,
                subtitleOverride: subtitle(for: task),
                statusView: statusView(for: task)
            ) {
                if task.state == .completed { play(song: song) }
            }
            if task.state != .completed {
                controls(for: task)
                    .padding(.trailing, Dimens.paddingMedium)
            }
        }
    }

    private func subtitle(for task: DownloadTask) -> String {
        if isEpisode(task) { return parityDurationText(task.songDurationSeconds) }
        return task.songGenreName ?? ""
    }

    /// `DownloadProgressWidget` (complete rows show nothing on this page).
    private func statusView(for task: DownloadTask) -> AnyView? {
        switch task.state {
        case .completed:
            return nil
        case .failed:
            return AnyView(
                Text("Downloading Failed")
                    .font(.custom(Typography.fontFamily, size: 8).weight(.bold))
                    .foregroundStyle(Color.red)
            )
        case .queued, .downloading, .paused:
            if let total = task.totalBytes, total > 0, task.bytesWritten > 0 {
                return AnyView(
                    ProgressView(value: Double(task.bytesWritten), total: Double(total))
                        .progressViewStyle(.linear)
                        .tint(Color.white)
                )
            }
            return AnyView(
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.white)
            )
        }
    }

    @ViewBuilder
    private func controls(for task: DownloadTask) -> some View {
        switch task.state {
        case .downloading:
            ParityIconButton(systemName: "pause.fill", size: 18, tooltip: "Pause", hitSize: 40) {
                downloadEngine.pause(songID: task.songID)
            }
        case .paused:
            HStack(spacing: 0) {
                ParityIconButton(systemName: "play.fill", size: 18, tooltip: "Resume", hitSize: 40) {
                    downloadEngine.resume(songID: task.songID)
                }
                ParityIconButton(systemName: "xmark", size: 18, tooltip: "Cancel", hitSize: 40) {
                    downloadEngine.cancel(songID: task.songID)
                }
            }
        case .failed:
            HStack(spacing: 0) {
                ParityIconButton(systemName: "arrow.clockwise", size: 18, tooltip: "Retry", hitSize: 40) {
                    Task { await downloadEngine.retry(songID: task.songID) }
                }
                ParityIconButton(systemName: "xmark", size: 18, tooltip: "Cancel", hitSize: 40) {
                    downloadEngine.cancel(songID: task.songID)
                }
            }
        case .queued:
            ParityIconButton(systemName: "xmark", size: 18, tooltip: "Cancel", hitSize: 40) {
                downloadEngine.cancel(songID: task.songID)
            }
        case .completed:
            EmptyView()
        }
    }

    // MARK: - Playback

    private var isThisQueueActive: Bool {
        queueController.queue?.source.playerID == Self.attribution.playerID
    }

    private var isPlaying: Bool {
        isThisQueueActive && audioEngine.status == .playing
    }

    private func togglePlayback() {
        if isThisQueueActive {
            if audioEngine.status == .playing { audioEngine.pause() } else { audioEngine.resume() }
            return
        }
        play(startIndex: 0)
    }

    private func play(song: Song) {
        if isThisQueueActive, queueController.queue?.currentSong?.id == song.id {
            if audioEngine.status == .playing { audioEngine.pause() } else { audioEngine.resume() }
            return
        }
        guard let index = completedVisibleSongs.firstIndex(where: { $0.id == song.id }) else { return }
        play(startIndex: index)
    }

    private func play(startIndex: Int) {
        let songs = completedVisibleSongs
        guard !songs.isEmpty else { return }
        Task {
            await queueController.play(songs: songs, startIndex: startIndex, source: Self.attribution)
            coordinator.presentPlayer()
        }
    }
}
