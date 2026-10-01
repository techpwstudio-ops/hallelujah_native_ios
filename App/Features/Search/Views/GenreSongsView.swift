import SwiftUI

/// Ports `GenreSongs` (`lib/views/search/category_songs.dart`): a header
/// (hero image, name, Shuffle, Play/Pause) and a paginated song list.
///
/// Left out, a deliberate scope cut: the "⋮" More button
/// (`showContentMenu`, `content_menu_sheet.dart`). For a genre specifically,
/// Dart's sheet shows exactly one gated row — "Add to queue"
/// (`AddSourceToQueueEvent`) — share/library rows never apply (share is
/// company-playlist-only; a genre carries no `libraryItemType` to save).
/// That action calls `QueueSourceService.fetchSongIds(source)`, an
/// independent fetch of the container's ENTIRE song list decoupled from
/// whatever's currently paginated on screen — infrastructure this app
/// doesn't have anywhere yet, not just here. Omitted rather than stubbed,
/// pending that mechanism landing for genre/playlist/album/season/creator
/// alike.
///
/// No collapsing `SliverAppBar` parallax — same "D10 doesn't apply to
/// Search" exemption `CreatorProfileView`'s header already relies on.
struct GenreSongsView: View {
    @State private var viewModel: GenreSongsViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    private static let heroHeight: CGFloat = 280
    private static let controlDiameter: CGFloat = 44

    init(genreID: String?, genreName: String?, genreImage: String?, genreImageVariants: String?) {
        _viewModel = State(initialValue: GenreSongsViewModel(
            genreID: genreID,
            genreName: genreName,
            genreImage: genreImage,
            genreImageVariants: genreImageVariants
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                songList
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(theme.color(.backgroundPrimary))
        .task { await viewModel.onAppear() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // `GeometryReader` for the container's actual width, not
            // `UIScreen.main` — same reasoning as `CreatorProfileView`'s
            // identical hero header.
            GeometryReader { proxy in
                ArtworkView(
                    url: ArtworkURLResolver().resolve(
                        path: viewModel.genreImage,
                        variant: .lg,
                        allowedVariants: viewModel.genreImageVariants
                    ),
                    width: proxy.size.width,
                    height: Self.heroHeight,
                    cornerRadius: 0,
                    contentMode: .fill
                )
            }
            .frame(height: Self.heroHeight)

            HStack(spacing: Spacing.md) {
                Text(viewModel.genreName ?? "")
                    .typography(Typography.headlineMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    Task { await queueController.toggleShuffle() }
                } label: {
                    theme.icon(.shuffle)
                        .font(.system(size: 18))
                        .foregroundStyle(queueController.isShuffled ? theme.color(.textPrimary) : theme.color(.textSecondary))
                }
                .buttonStyle(.plain)

                Button(action: togglePlayback) {
                    ZStack {
                        Circle().fill(theme.color(.textPrimary))
                        theme.icon(isPlaying ? .pause : .play)
                            .font(.system(size: 20))
                            .foregroundStyle(theme.color(.backgroundPrimary))
                    }
                    .frame(width: Self.controlDiameter, height: Self.controlDiameter)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.songs.isEmpty)
                .opacity(viewModel.songs.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Playback

    private func attribution(genreID: String) -> QueueAttribution {
        QueueAttribution(playerType: .genre, id: genreID, title: viewModel.genreName ?? "")
    }

    private var isThisGenreQueueActive: Bool {
        guard let genreID = viewModel.genreID else { return false }
        return queueController.queue?.source.playerID == attribution(genreID: genreID).playerID
    }

    private var isPlaying: Bool {
        isThisGenreQueueActive && audioEngine.status == .playing
    }

    private func togglePlayback() {
        if isThisGenreQueueActive {
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

    /// Matches `PlayerBloc`'s `PlaySongEvent` early-return (`bloc.dart`):
    /// tapping the row of the song already playing in THIS genre's queue
    /// toggles play/pause in place — no restart from 0:00, no navigation to
    /// the full player. Any other tap is a genuine song change, which still
    /// starts fresh (and still navigates), same as the header's play button.
    private func play(song: Song) {
        if isThisGenreQueueActive, queueController.queue?.currentSong?.id == song.id {
            togglePlayPause()
            return
        }
        guard let startIndex = viewModel.songs.firstIndex(where: { $0.id == song.id }) else { return }
        play(startIndex: startIndex)
    }

    private func play(startIndex: Int) {
        guard let genreID = viewModel.genreID, !viewModel.songs.isEmpty else { return }
        let songs = viewModel.songs
        Task {
            await queueController.play(songs: songs, startIndex: startIndex, source: attribution(genreID: genreID))
            coordinator.presentPlayer()
        }
    }

    // MARK: - Songs

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.songs) { song in
                CreatorSongRow(song: song) { play(song: song) }
                    .padding(.horizontal, Spacing.md)
                    .task { await viewModel.loadMoreSongsIfNeeded(currentItem: song) }
            }
            if viewModel.isLoadingSongs {
                LoadingStateView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.hasLoadedOnce, viewModel.songs.isEmpty {
                EmptyStateView(title: "No songs yet")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }
}
