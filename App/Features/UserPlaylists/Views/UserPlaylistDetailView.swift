import SwiftUI

/// Ports `UserPlaylistSongs` (`lib/views/library/user_playlist_songs.dart`):
/// a hero header (cover, title, song count, Shuffle, Play/Pause) over a
/// paginated song list, plus three owner-only admin affordances Dart gates
/// on `isAdmin` the same way — "Add songs", a per-row remove button, and a
/// "..." menu (Rename/Delete). Non-owner viewers get the same header and a
/// plain, read-only list, matching `PlaylistDetailView`'s own style.
///
/// `playlistID` may be `nil` — `AppRoute.userPlaylistSongs`'s own payload
/// shape — handled the same defensive way
/// `UserPlaylistDetailViewModel.load(page:)` documents: `.failed`, so this
/// view falls through to `ErrorStateView`'s retry rather than spinning.
///
/// Scope cuts (T45, deliberate): drag-to-reorder, visibility toggle,
/// follow/unfollow, share, add-to-queue, cover-image upload — none of these
/// have a trigger here, matching Dart's own `isAdmin`-only "Add songs"/
/// "..." pair (Follow/Share are non-owner Dart affordances this rewrite
/// doesn't port either, per T45's scope-cut list).
struct UserPlaylistDetailView: View {
    @State private var viewModel: UserPlaylistDetailViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var showAddSongs = false
    @State private var isDeleteConfirmationPresented = false

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    private static let heroHeight: CGFloat = 280
    private static let controlDiameter: CGFloat = 44

    init(playlistID: String?) {
        _viewModel = State(initialValue: UserPlaylistDetailViewModel(playlistID: playlistID))
    }

    /// The header's own playlist, pulled out of `LoadState` — both
    /// `.loaded`/`.empty` carry one, `.loading`/`.failed` don't.
    private var playlist: UserPlaylist? {
        switch viewModel.state {
        case .loaded(let playlist, _): playlist
        case .empty(let playlist): playlist
        case .loading, .failed: nil
        }
    }

    private var songs: [Song] {
        if case .loaded(_, let page) = viewModel.state { return page.items }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch viewModel.state {
                case .loading:
                    LoadingStateView()
                case .failed:
                    ErrorStateView(
                        title: "Couldn't load this playlist",
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                case .empty(let playlist):
                    header(playlist: playlist)
                    EmptyStateView(title: "No songs yet")
                        .frame(maxWidth: .infinity, minHeight: 160)
                case .loaded(let playlist, let page):
                    header(playlist: playlist)
                    songList(page: page)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(theme.color(.backgroundPrimary))
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.loadIfNeeded() }
        .toolbar {
            if viewModel.isOwner, let playlist = playlist {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add songs") { showAddSongs = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rename") {
                            coordinator.push(.createPlaylist(userPlaylistID: playlist.id, songType: nil, songID: nil))
                        }
                        Button("Delete", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    } label: {
                        theme.icon(.more)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSongs, onDismiss: { Task { await viewModel.refresh() } }) {
            if let playlist = playlist {
                AddSongsToPlaylistView(playlistID: playlist.id)
            }
        }
        .confirmationDialog(
            "Delete this playlist?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deletePlaylist() {
                        coordinator.pop()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private func header(playlist: UserPlaylist) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // `GeometryReader` for the container's actual width, not
            // `UIScreen.main` — same reasoning as `GenreSongsView`'s
            // identical hero header.
            GeometryReader { proxy in
                ArtworkView(
                    url: ArtworkURLResolver().resolve(
                        path: playlist.image,
                        variant: .lg,
                        allowedVariants: playlist.imageVariants
                    ),
                    width: proxy.size.width,
                    height: Self.heroHeight,
                    cornerRadius: 0,
                    contentMode: .fill
                )
            }
            .frame(height: Self.heroHeight)

            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(playlist.title)
                        .typography(Typography.headlineMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                        .lineLimit(1)
                    if let songsCount = playlist.songsCount {
                        Text("\(songsCount) songs")
                            .typography(Typography.bodySmall)
                            .foregroundStyle(theme.color(.textSecondary))
                    }
                }

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
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Playback

    private func attribution(playlist: UserPlaylist) -> QueueAttribution {
        QueueAttribution(playerType: .userPlaylist, id: playlist.id, title: playlist.title)
    }

    private var isThisPlaylistQueueActive: Bool {
        guard let playlist else { return false }
        return queueController.queue?.source.playerID == attribution(playlist: playlist).playerID
    }

    private var isPlaying: Bool {
        isThisPlaylistQueueActive && audioEngine.status == .playing
    }

    private func togglePlayback() {
        if isThisPlaylistQueueActive {
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

    /// Matches `PlayerBloc`'s `PlaySongEvent` early-return, same as
    /// `GenreSongsView.play(song:)`: tapping the row of the song already
    /// playing in THIS playlist's queue toggles play/pause in place.
    private func play(song: Song) {
        if isThisPlaylistQueueActive, queueController.queue?.currentSong?.id == song.id {
            togglePlayPause()
            return
        }
        guard let startIndex = songs.firstIndex(where: { $0.id == song.id }) else { return }
        play(startIndex: startIndex)
    }

    private func play(startIndex: Int) {
        guard let playlist, !songs.isEmpty else { return }
        let songsToPlay = songs
        Task {
            await queueController.play(songs: songsToPlay, startIndex: startIndex, source: attribution(playlist: playlist))
            coordinator.presentPlayer()
        }
    }

    // MARK: - Songs

    private func songList(page: Paginated<Song>) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(page.items.enumerated()), id: \.element.id) { index, song in
                row(song: song)
                    .onAppear {
                        guard index >= page.items.count - 2 else { return }
                        viewModel.loadMore()
                    }
            }
        }
    }

    /// Dart's own remove-from-playlist trigger lives inside the shared "..."
    /// song action sheet (`song_menu_sheet.dart:68-81`, gated on
    /// `userPlaylistId != null`), which doesn't exist anywhere in this app
    /// yet — `CreatorSongRow`'s own doc comment and T44's status log both
    /// already name this gap. `.swipeActions` can't stand in for it either:
    /// it's documented to work only on `List` row content, and this screen's
    /// song list is a `LazyVStack`/`ScrollView` (matching every other song
    /// list in this app), where the modifier silently no-ops. A plain
    /// trailing icon button is the smallest affordance that's actually
    /// interactive here.
    private func row(song: Song) -> some View {
        HStack(spacing: Spacing.sm) {
            CreatorSongRow(song: song) { play(song: song) }
            if viewModel.isOwner {
                Button {
                    Task { await viewModel.removeSong(id: song.id) }
                } label: {
                    theme.icon(.trash)
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
    }
}
