import SwiftUI

/// Ports `GenreSongs` (`lib/views/search/category_songs.dart`): a full-bleed
/// hero (`width * 3/4` tall, extending under the status bar, scrimmed by
/// `GradiantDecoratedBox`), a title row (`headlineSmall` + Shuffle + "more" +
/// Play/Pause, 16/8 padding) and the paginated `SongListItem` list (8pt side
/// padding). Empty states: spinner while the first page loads, otherwise
/// "Content not available". The "more" sheet offers the one row Dart shows
/// for a genre, "Add to queue" (of the songs loaded so far).
///
/// Not ported: the collapsing/parallax `SliverAppBar` and the fade-in
/// collapsed title (the shell's nav bar shows the title).
struct GenreSongsView: View {
    @State private var viewModel: GenreSongsViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var showsMore = false
    @State private var showsCollapsedTitle = false

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

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
            VStack(alignment: .leading, spacing: 0) {
                ParityHeroImage(
                    url: ArtworkURLResolver().resolve(
                        path: viewModel.genreImage,
                        variant: .lg,
                        allowedVariants: viewModel.genreImageVariants
                    ),
                    aspect: 4.0 / 3.0
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: GenreHeroMaxYKey.self,
                            value: proxy.frame(in: .named("genreScroll")).maxY
                        )
                    }
                )
                titleRow
                songList
                Color.clear.frame(height: 16)
            }
        }
        .coordinateSpace(name: "genreScroll")
        .onPreferenceChange(GenreHeroMaxYKey.self) { maxY in
            // `offset > expandedHeight - kToolbarHeight - 40`.
            let shouldShow = maxY < 150
            if shouldShow != showsCollapsedTitle { showsCollapsedTitle = shouldShow }
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .top)
        .appNavigationBarBackground(isVisible: showsCollapsedTitle)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.genreName ?? "")
                    .font(.custom(Typography.fontFamily, size: 16).weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .opacity(showsCollapsedTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showsCollapsedTitle)
            }
        }
        .task { await viewModel.onAppear() }
        .appSheet(isPresented: $showsMore, detents: [.medium]) {
            VStack(alignment: .leading, spacing: 0) {
                SongMenuRow(systemImage: "text.badge.plus", title: "Add to queue") {
                    showsMore = false
                    addToQueue()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack(spacing: 0) {
            Text(viewModel.genreName ?? "")
                .typography(ParityHeroText.headlineSmall)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            ParityShuffleButton(isOn: queueController.isShuffled) {
                Task { await queueController.toggleShuffle() }
            }
            ParityIconButton(systemName: "ellipsis", rotation: 90, tooltip: "More") { showsMore = true }
            ParityPlayPauseButton(isPlaying: isPlaying) { togglePlayback() }
                .opacity(viewModel.songs.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, Dimens.screenPaddingAll * 2)
        .padding(.vertical, Dimens.screenPaddingAll)
    }

    private func addToQueue() {
        guard let genreID = viewModel.genreID, !viewModel.songs.isEmpty else { return }
        let songs = viewModel.songs
        Task {
            let added = await queueController.addToQueue(songs, source: attribution(genreID: genreID))
            toastCenter.show(added > 0 ? String(localized: "Added to queue") : String(localized: "Already in your queue"))
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

    @ViewBuilder
    private var songList: some View {
        if viewModel.songs.isEmpty {
            if viewModel.isLoadingSongs || !viewModel.hasLoadedOnce {
                ParitySpinner(fills: true)
            } else {
                ParityEmptyText(text: "Content not available")
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.songs) { song in
                    CreatorSongRow(song: song) { play(song: song) }
                        .task { await viewModel.loadMoreSongsIfNeeded(currentItem: song) }
                }
                if viewModel.isLoadingSongs {
                    ParitySpinner()
                }
            }
            .padding(.horizontal, Dimens.screenPaddingAll)
        }
    }
}

private struct GenreHeroMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
