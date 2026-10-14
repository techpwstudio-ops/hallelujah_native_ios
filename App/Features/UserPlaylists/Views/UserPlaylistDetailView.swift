import SwiftUI

/// Ports `UserPlaylistSongs` (`lib/views/library/user_playlist_songs.dart`):
/// a square full-bleed hero (scrim stops 0 / 0.35 / 0.7 / 1.0 to black, a
/// "more" menu top-right), an info block (title `headlineSmall`, visibility
/// glyph + "<Visibility> · <duration>" in `labelSmall` white60, an action row
/// with owner-only "add songs", Shuffle and Play), then the song list (8pt
/// side padding; the song menu offers remove-from-playlist for the owner).
/// The info block and the first 8 rows ease in (fade + slide, staggered over
/// 750ms like `_entranceController`). Empty states: "Playlist not found",
/// spinner, "No songs yet".
///
/// Not ported (no repository support): the owner's name line, the non-owner
/// Follow button and the Share button.
struct UserPlaylistDetailView: View {
    @State private var viewModel: UserPlaylistDetailViewModel
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var audioEngine: AudioEngine = DependencyContainer.current.resolve()
    @State private var showAddSongs = false
    @State private var menuTarget: UserPlaylistMenuTarget?

    @Environment(AppNavigationCoordinator.self) private var coordinator

    private static let staggerCount = 8

    init(playlistID: String?) {
        _viewModel = State(initialValue: UserPlaylistDetailViewModel(playlistID: playlistID))
    }

    /// The header's own playlist, pulled out of `LoadState`.
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
        Group {
            switch viewModel.state {
            case .loading:
                ParitySpinner(fills: true).frame(maxHeight: .infinity)
            case .failed:
                ParityEmptyText(text: "Playlist not found").frame(maxHeight: .infinity)
            case .empty(let playlist):
                scroll(playlist: playlist, page: nil)
            case .loaded(let playlist, let page):
                scroll(playlist: playlist, page: page)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .toolbar {
            if let playlist {
                ToolbarItem(placement: .primaryAction) {
                    ParityIconButton(systemName: "ellipsis", rotation: 90, tooltip: "More") {
                        menuTarget = UserPlaylistMenuTarget(id: playlist.id, title: playlist.title)
                    }
                }
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .userPlaylistMenu(target: $menuTarget) { coordinator.pop() }
        .sheet(isPresented: $showAddSongs, onDismiss: { Task { await viewModel.refresh() } }) {
            if let playlist {
                AddSongsToPlaylistView(playlistID: playlist.id)
            }
        }
    }

    private func scroll(playlist: UserPlaylist, page: Paginated<Song>?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ParityHeroImage(
                    url: ArtworkURLResolver().resolve(
                        path: playlist.image,
                        variant: .lg,
                        allowedVariants: playlist.imageVariants
                    ),
                    aspect: 1,
                    stops: ParityHeroImage.playlistStops
                )

                info(playlist: playlist)
                    .parityEntrance(delay: 0.0375, duration: 0.375, offset: 28)

                if let page {
                    songList(page: page)
                } else {
                    ParityEmptyText(text: "No songs yet")
                }
                Color.clear.frame(height: 168)
            }
        }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Info

    private func info(playlist: UserPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(playlist.title)
                .typography(ParityHeroText.headlineSmall)
                .foregroundStyle(Color.white)

            Spacer().frame(height: 6)
            Spacer().frame(height: 8)

            HStack(spacing: 4) {
                Image(systemName: playlist.visibility == "public" ? "globe" : "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(ParityColor.white60)
                Text(visibilityLine(for: playlist))
                    .typography(ParityHeroText.labelSmall)
                    .foregroundStyle(ParityColor.white60)
            }

            Spacer().frame(height: 4)

            HStack(spacing: 0) {
                if viewModel.isOwner {
                    ParityIconButton(systemName: "plus.circle", size: 24, tooltip: "Add songs", frame: 40) {
                        showAddSongs = true
                    }
                }
                Spacer(minLength: 0)
                ParityShuffleButton(isOn: queueController.isShuffled) {
                    Task { await queueController.toggleShuffle() }
                }
                Spacer().frame(width: 4)
                ParityPlayPauseButton(isPlaying: isPlaying) { togglePlayback() }
                    .opacity(songs.isEmpty ? 0.5 : 1)
            }

            Spacer().frame(height: 8)
        }
        .padding(.leading, Dimens.screenPaddingAll * 2)
        .padding(.trailing, Dimens.screenPaddingAll * 2)
        .padding(.top, 6)
    }

    private func visibilityLine(for playlist: UserPlaylist) -> String {
        let visibility = (playlist.visibility ?? "").parityCapitalized
        return visibility + " \u{00B7} " + parityDurationText(playlist.duration)
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

    /// Matches `PlayerBloc`'s `PlaySongEvent` early-return: tapping the row of
    /// the song already playing in THIS playlist's queue toggles play/pause.
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
                row(song: song, index: index)
                    .onAppear {
                        guard index >= page.items.count - 2 else { return }
                        viewModel.loadMore()
                    }
            }
            if viewModel.isLoadingMore {
                ParitySpinner()
            }
        }
        .padding(.horizontal, Dimens.screenPaddingAll)
    }

    @ViewBuilder
    private func row(song: Song, index: Int) -> some View {
        let item = CreatorSongRow(song: song, userPlaylistID: viewModel.isOwner ? playlist?.id : nil) {
            play(song: song)
        }
        if index < Self.staggerCount {
            let start = min(max(0.2 + Double(index) * 0.07, 0), 0.75)
            item.parityEntrance(delay: start * 0.75, duration: 0.32 * 0.75, offset: 13)
        } else {
            item
        }
    }
}
