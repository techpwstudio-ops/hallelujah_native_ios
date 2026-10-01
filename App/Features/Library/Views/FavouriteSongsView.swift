import SwiftUI

/// Ports `FavouriteSongsScreen` (`lib/views/library/favourite_songs_list.dart`):
/// a 220pt gradient header (label, count, Shuffle, Play) over the paginated
/// "already-favourited" song list. No per-row heart — see
/// `FavouriteSongsViewModel`'s own doc comment for why that's a deliberate,
/// grounded scope match rather than a gap.
///
/// No collapsing `SliverAppBar` parallax and no custom `BackButton()` —
/// same "D10 doesn't apply here, the system nav bar already does this job"
/// reasoning `GenreSongsView`/`CreatorProfileView` already established.
struct FavouriteSongsView: View {
    @State private var viewModel: FavouriteSongsViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    // T47 — offline library filtering: de-emphasizes rows that can't play
    // with no network rather than filtering them out of the list.
    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(NetworkStatusStore.self) private var networkStatus
    @Environment(\.appTheme) private var theme

    private static let headerHeight: CGFloat = 220
    private static let controlDiameter: CGFloat = 44
    /// `ColorTheme.favouriteBgTopColor` (`Color(0xFFE35A11)`) — a fixed
    /// literal like `AuthColors`' own, but kept local here rather than
    /// added there: that enum is scoped to the D10 pixel-parity auth
    /// screens specifically (its own doc comment says so), and this
    /// gradient is a decorative header on a non-D10 screen, not parity-
    /// mandated.
    private static let gradientTop = Color(red: 0xE3 / 255, green: 0x5A / 255, blue: 0x11 / 255)

    init(type: String?, label: String) {
        _viewModel = State(initialValue: FavouriteSongsViewModel(type: type, label: label))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                songList
                    .padding(.horizontal, Spacing.md)
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(theme.color(.backgroundPrimary))
        .task { await viewModel.onAppear() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Text(viewModel.label)
                    .typography(Typography.headlineMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    Task { await queueController.toggleShuffle() }
                } label: {
                    theme.icon(.shuffle)
                        .font(.system(size: 18))
                        .foregroundStyle(queueController.isShuffled ? .white : .white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: togglePlayback) {
                    ZStack {
                        Circle().fill(Color.white)
                        theme.icon(isPlaying ? .pause : .play)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.black)
                    }
                    .frame(width: Self.controlDiameter, height: Self.controlDiameter)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.songs.isEmpty)
                .opacity(viewModel.songs.isEmpty ? 0.5 : 1)
            }

            Text("\(viewModel.songCount) \(viewModel.typeName)")
                .typography(Typography.bodyMedium)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: Self.headerHeight, alignment: .bottomLeading)
        .background(
            LinearGradient(colors: [Self.gradientTop, .black], startPoint: .top, endPoint: .bottom)
        )
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

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.songs) { song in
                CreatorSongRow(song: song) { play(song: song) }
                    .opacity(isDeemphasized(song) ? 0.4 : 1)
                    .task { await viewModel.loadMoreSongsIfNeeded(currentItem: song) }
            }
            if viewModel.isLoadingSongs {
                LoadingStateView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.hasLoadedOnce, viewModel.songs.isEmpty {
                EmptyStateView(title: "No liked \(viewModel.typeName.lowercased())")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }

    /// T47 — offline library filtering: no Dart precedent (grepped
    /// lib/views/library/ for "offline"/connectivity-gated filtering, found
    /// nothing), so this stays a narrow, additive visual cue rather than a
    /// rebuild of the list. Rows stay in place and stay tappable either way —
    /// only a song that's both offline AND not on disk gets dimmed.
    private func isDeemphasized(_ song: Song) -> Bool {
        networkStatus.isOffline && !downloadEngine.isDownloaded(songID: song.id)
    }
}
