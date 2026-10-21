import SwiftUI

/// Ports `FavouriteSongsScreen` (`lib/views/library/favourite_songs_list.dart`):
/// a 220pt `#E35A11 -> black` gradient header ("Liked Music"/"Liked Episodes"
/// 26pt bold, Shuffle + Play, "<n> Music" subtitle in white70) over the
/// paginated list of `SongListItem`s (8pt padding, 6pt row insets). Spinner
/// while loading, "No <type>" when empty. Dart animates inserts/removals with
/// `ImplicitlyAnimatedList`; the list here animates nothing on removal.
struct FavouriteSongsView: View {
    @State private var viewModel: FavouriteSongsViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    // T47 — offline library filtering: de-emphasizes rows that can't play
    // with no network rather than filtering them out of the list.
    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(NetworkStatusStore.self) private var networkStatus

    /// `ColorTheme.favouriteBgTopColor` (0xFFE35A11).
    private static let gradientTop = Color(red: 0xE3 / 255, green: 0x5A / 255, blue: 0x11 / 255)

    init(type: String?, label: String) {
        _viewModel = State(initialValue: FavouriteSongsViewModel(type: type, label: label))
    }

    var body: some View {
        ParityGradientHeader(
            top: Self.gradientTop,
            title: viewModel.likedTitle,
            subtitle: viewModel.countText,
            isShuffled: queueController.isShuffled,
            isPlaying: isPlaying,
            onShuffle: { Task { await queueController.toggleShuffle() } },
            onPlay: { togglePlayback() },
            extra: { EmptyView() },
            content: { songList }
        )
        .background(Color.black)
        .task { await viewModel.onAppear() }
    }

    // MARK: - Playback

    private var attribution: QueueAttribution {
        QueueAttribution(playerType: .favourite, id: viewModel.attributionID, title: viewModel.label)
    }

    private var isThisQueueActive: Bool {
        queueController.queue?.source.playerID == attribution.playerID
    }

    private var isPlaying: Bool {
        isThisQueueActive && audioEngine.status == .playing
    }

    private func togglePlayback() {
        if isThisQueueActive {
            togglePlayPause()
            return
        }
        play(startIndex: 0)
    }

    private func togglePlayPause() {
        if audioEngine.status == .playing {
            audioEngine.pause()
        } else {
            audioEngine.resume()
        }
    }

    /// Same `PlayerBloc`'s `PlaySongEvent` early-return `GenreSongsView.play(song:)`
    /// already documents: tapping the row of the song already playing in
    /// THIS favourites queue toggles play/pause in place rather than
    /// restarting.
    private func play(song: Song) {
        if isThisQueueActive, queueController.queue?.currentSong?.id == song.id {
            togglePlayPause()
            return
        }
        guard let startIndex = viewModel.songs.firstIndex(where: { $0.id == song.id }) else { return }
        play(startIndex: startIndex)
    }

    private func play(startIndex: Int) {
        guard !viewModel.songs.isEmpty else { return }
        let songs = viewModel.songs
        Task {
            await queueController.play(songs: songs, startIndex: startIndex, source: attribution)
            coordinator.presentPlayer()
        }
    }

    // MARK: - Songs

    @ViewBuilder
    private var songList: some View {
        if viewModel.songs.isEmpty {
            if viewModel.isLoadingSongs || !viewModel.hasLoadedOnce {
                ParitySpinner(fills: true)
            } else {
                ParityEmptyText(text: LocalizedStringKey(viewModel.emptyText))
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.songs) { song in
                        CreatorSongRow(song: song) { play(song: song) }
                            .padding(.vertical, Dimens.verticalSpacing / 2)
                            .opacity(isDeemphasized(song) ? 0.4 : 1)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                            .task { await viewModel.loadMoreSongsIfNeeded(currentItem: song) }
                    }
                    if viewModel.isLoadingSongs {
                        ParitySpinner()
                    }
                    Color.clear.frame(height: 16)
                }
                // `ImplicitlyAnimatedList`: 300ms fade/slide on insert and remove.
                .animation(.easeOut(duration: 0.3), value: viewModel.songs.map { $0.id })
                .padding(Dimens.screenPaddingAll)
                // Native-only tablet/Mac adaptation (no Flutter counterpart).
                .readableContentWidth()
            }
        }
    }

    /// T47 — offline library filtering (no Dart precedent): rows stay in
    /// place and tappable; only a song that is both offline AND not on disk
    /// gets dimmed.
    private func isDeemphasized(_ song: Song) -> Bool {
        networkStatus.isOffline && !downloadEngine.isDownloaded(songID: song.id)
    }
}
