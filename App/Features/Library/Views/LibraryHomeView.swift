import SwiftUI

/// Ports `LibraryPage` (`lib/views/library/library.dart`): app bar "Library"
/// with a trailing "Create" button (32pt, radius 8, "+" icon), the tap-through
/// `SearchWidgetUi` bar, an All / Music / Podcast `SongTypeTopNavigationButton`
/// row (16pt gap, 16pt inset), the conditional `LibraryUi` quick tiles
/// (Downloads for All, Liked Music for All/Music, Liked Episodes for
/// All/Episode, Liked Artists always) and the merged `LibraryListItem` list.
/// Spacing between sections is `Dimens.verticalSpacing` (12); 8pt page
/// padding; a 96pt bottom bar; pull-to-refresh reloads everything.
struct LibraryHomeView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var downloadEngine: DownloadEngine = DependencyContainer.current.resolve()
    @State private var eventBus: RealtimeEventBus = DependencyContainer.current.resolve()
    @State private var contentMenuTarget: ContentMenuTarget?
    @State private var userPlaylistMenuTarget: UserPlaylistMenuTarget?

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase

    private var downloadCount: Int {
        // Flutter's `DownloadBloc` lists a task from the moment it is
        // enqueued (`_downloadSong` → `LoadDownloadsEvent`), not when it
        // finishes, so the tile counts every task the Downloads page shows.
        downloadEngine.tasks.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ParityFakeSearchBar {
                    coordinator.push(.contentSearch(userPlaylistID: nil, tags: [], checkedContent: [], isSelect: false))
                }

                Spacer().frame(height: Dimens.verticalSpacing)

                filterRow
                    .padding(.horizontal, Dimens.screenPaddingAll)

                Spacer().frame(height: Dimens.verticalSpacing)

                quickLinks

                itemList

                // `BottomSizeBar` (96) + `Ios26BottomSpacing` (56) over the floating dock.
                DockClearance()
            }
            .padding(.horizontal, Dimens.screenPaddingAll)
        }
        .background(Color.black)
        .refreshable { await viewModel.refresh() }
        .task(id: viewModel.filter) { await viewModel.load() }
        // `users.playlist.updated`: a playlist's server-composited cover has landed.
        .onChange(of: eventBus.playlistUpdateCount) { _, _ in
            Task { await viewModel.silentRefresh() }
        }
        // The push is best-effort, so also re-check whenever the tab is shown
        // again (back from a playlist, another tab) or the app returns to the
        // foreground. No-op before the first load finishes.
        .onAppear { Task { await viewModel.silentRefresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .favouriteSongsDidChange)) { _ in
            Task { await viewModel.silentRefresh() }
        }
        .onDisappear { viewModel.stopCoverPoll() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.silentRefresh() }
        }
        .contentMenu(target: $contentMenuTarget)
        .userPlaylistMenu(target: $userPlaylistMenuTarget) {
            Task { await viewModel.refresh() }
        }
        .toolbar {
            createToolbarItem
        }
    }

    /// On iOS 26 the system wraps a toolbar button in its own glass capsule, and
    /// `createButton` draws one too, which read as two stacked glass buttons. The
    /// shared background is switched off so only the button's own capsule shows.
    @ToolbarContentBuilder
    private var createToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                createButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                createButton
            }
        }
    }

    /// `FilledButton.icon(Icons.add, "Create")` at 32pt height, radius 8.
    private var createButton: some View {
        Button {
            coordinator.push(.createPlaylist(userPlaylistID: nil, songType: nil, songID: nil))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                Text("Create")
                    .typography(Typography.labelLarge)
            }
            .foregroundStyle(Color.white)
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(height: 32)
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: Dimens.horizontalSpacing) {
            ParityTypeButton(title: "All", isSelected: viewModel.filter == .all) { viewModel.filter = .all }
            ParityTypeButton(title: "Music", isSelected: viewModel.filter == .music) { viewModel.filter = .music }
            ParityTypeButton(title: "Podcast", isSelected: viewModel.filter == .episode) { viewModel.filter = .episode }
        }
    }

    // MARK: - Quick links

    /// `LibraryUi`: Downloads only for `.all`; Liked Music for `.all`/`.music`;
    /// Liked Episodes for `.all`/`.episode`; Liked Artists always. While the
    /// counts load each liked tile is a shimmer skeleton.
    @ViewBuilder
    private var quickLinks: some View {
        VStack(spacing: 0) {
            if viewModel.filter == .all {
                LibraryQuickLinkRow(
                    assetName: "downloads",
                    fallbackSymbol: "arrow.down.circle",
                    title: "Downloads",
                    count: downloadCount
                ) {
                    coordinator.push(.downloads(type: viewModel.filter.rawValue))
                }
            }

            if viewModel.isLoadingCounts, viewModel.counts == nil {
                countsSkeleton
            } else {
                if viewModel.filter == .all || viewModel.filter == .music {
                    LibraryQuickLinkRow(
                        assetName: "liked_musics",
                        fallbackSymbol: "heart.fill",
                        title: "Liked Music",
                        count: viewModel.counts?.likedMusic ?? 0
                    ) {
                        coordinator.push(.favouriteSongs(type: "music", label: String(localized: "Liked Music"), asset: "liked_musics"))
                    }
                }
                if viewModel.filter == .all || viewModel.filter == .episode {
                    LibraryQuickLinkRow(
                        assetName: "liked_episode",
                        fallbackSymbol: "heart.fill",
                        title: "Liked Episodes",
                        count: viewModel.counts?.likedEpisodes ?? 0
                    ) {
                        coordinator.push(.favouriteSongs(type: "episode", label: String(localized: "Liked Episodes"), asset: "liked_episode"))
                    }
                }
                LibraryQuickLinkRow(
                    assetName: "liked_artists",
                    fallbackSymbol: "music.mic",
                    title: "Liked Artists",
                    count: viewModel.counts?.likedArtists ?? 0
                ) {
                    coordinator.push(.favouriteArtists(songType: viewModel.filter.rawValue))
                }
            }
        }
    }

    private var countsSkeleton: some View {
        VStack(spacing: 0) {
            if viewModel.filter == .all || viewModel.filter == .music {
                LibraryQuickLinkSkeleton()
            }
            if viewModel.filter == .all || viewModel.filter == .episode {
                LibraryQuickLinkSkeleton()
            }
            LibraryQuickLinkSkeleton()
        }
        .shimmer()
    }

    // MARK: - Merged list

    private var itemList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.items) { entry in
                LibraryEntryRow(entry: entry, onMore: { openMenu(for: entry) }) { open(entry) }
                    .task { await viewModel.loadMoreItemsIfNeeded(currentItem: entry) }
            }
            if viewModel.isLoadingItems {
                ParitySpinner()
            }
        }
    }

    private func openMenu(for entry: LibraryEntry) {
        switch entry {
        case let .playlist(playlist):
            contentMenuTarget = .playlist(playlist)
        case let .userPlaylist(id, title, image, imageVariants, _, _, _):
            userPlaylistMenuTarget = UserPlaylistMenuTarget(
                id: id,
                title: title,
                artworkURL: ArtworkURLResolver().resolve(path: image, variant: .lg, allowedVariants: imageVariants, fallbackName: title)
            )
        }
    }

    private func open(_ entry: LibraryEntry) {
        switch entry {
        case let .playlist(playlist):
            let isCompany = playlist.owner == .company
            var creatorID: String?
            var creatorName: String?
            if case let .creator(id, name) = playlist.owner {
                creatorID = id
                creatorName = name
            }
            coordinator.push(.playlistDetail(
                playlistID: playlist.id,
                title: playlist.title,
                image: playlist.image,
                imageVariants: playlist.imageVariants,
                songsCount: playlist.songsCount,
                isCompanyOwned: isCompany,
                creatorID: creatorID,
                creatorName: creatorName
            ))
        case let .userPlaylist(id, _, _, _, _, _, _):
            coordinator.push(.userPlaylistSongs(playlistID: id))
        }
    }
}
