import SwiftUI

/// Ports `content_search_page.dart` + `SearchBloc`. Layout (`_ContentSearchPageState`):
/// a 200pt `darkFillColor -> darkSurface -> black` gradient behind a
/// back-arrow + field bar (52pt, `#333333`, radius 6, 16/8/16/12 inset), an
/// optional 40pt filter-chip row once text is typed, then one of: recent
/// searches (empty field), shimmer (loading / debounce window), "No results
/// found", the "All" overview (Top Result + 5-item sections with "See all"),
/// or one paginated section with a load-more shimmer and an end message.
///
/// Not ported: the locked
/// select-mode entry points (`searchUiItemType`/`isSelect`, which drive the
/// add-songs/add-artists pickers — native has its own `AddSongsToPlaylistView`).
struct ContentSearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @State private var menuTarget: ContentMenuTarget?
    @FocusState private var isFieldFocused: Bool
    @State private var isListening = false

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    private static let topAnchor = "content-search-top"

    private var trimmedQuery: String {
        viewModel.searchFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSongID: String? { queueController.queue?.currentSong?.id }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [ParityColor.darkFill, ParityColor.darkSurface, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                searchBar
                if !trimmedQuery.isEmpty {
                    filterBar
                }
                resultsBody
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .contentMenu(target: $menuTarget)
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Dimens.paddingMedium)
            Button { coordinator.pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer().frame(width: Dimens.paddingMedium)

            TextField(
                "",
                text: Binding(
                    get: { viewModel.searchFieldText },
                    set: { viewModel.queryChanged($0) }
                ),
                prompt: Text(isListening ? "Listening\u{2026}" : "What do you want to listen to?").foregroundColor(ParityColor.grey)
            )
            .typography(Typography.bodyMedium)
            .foregroundStyle(Color.white)
            .tint(ParityColor.white70)
            .focused($isFieldFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()

            VoiceSearchButton(
                onResult: { text, _ in viewModel.queryChanged(text) },
                onListeningChanged: { listening in
                    isListening = listening
                    if listening { isFieldFocused = false }
                }
            )
            if !viewModel.searchFieldText.isEmpty {
                Button { viewModel.clearButtonTapped() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20))
                        .foregroundStyle(ParityColor.white60)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Spacer().frame(width: Dimens.spacing4)
        }
        .frame(height: Dimens.buttonHeight)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall + 2, style: .continuous)
                .fill(ParityColor.searchBar)
                .shadow(color: Color.black.opacity(0.3), radius: Dimens.spacing8 / 2, x: 0, y: 2)
        )
        .padding(.leading, Dimens.screenPadding)
        .padding(.trailing, Dimens.screenPadding)
        .padding(.top, Dimens.spacing8)
        .padding(.bottom, Dimens.paddingMedium)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Dimens.spacing8) {
                SearchFilterChip(label: "All", isSelected: viewModel.activeFilter == nil) {
                    viewModel.selectFilter(nil)
                }
                ForEach(SearchFilter.allCases, id: \.rawValue) { filter in
                    SearchFilterChip(label: filter.title, isSelected: viewModel.activeFilter == filter) {
                        viewModel.selectFilter(filter)
                    }
                }
            }
            .padding(.horizontal, Dimens.screenPadding)
        }
        .frame(height: 40)
        .padding(.bottom, Dimens.spacing8)
    }

    // MARK: - Body

    @ViewBuilder
    private var resultsBody: some View {
        if viewModel.searchFieldText.isEmpty {
            recentSearchesSection
        } else if viewModel.isBusy {
            ScrollView { ParityShimmerList() }
                .scrollDisabled(true)
        } else if !viewModel.hasAnyResults {
            ParityEmptyState(
                systemImage: "magnifyingglass",
                title: "No results found",
                message: "Try searching with a different keyword"
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: Dimens.spacing8).id(Self.topAnchor)
                        if viewModel.isOverview {
                            overviewContent
                        } else {
                            filteredContent
                        }
                        Color.clear.frame(height: 96)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: viewModel.activeFilter) { _, _ in
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        }
    }

    // MARK: - Recent searches

    @ViewBuilder
    private var recentSearchesSection: some View {
        if viewModel.recentSearchStore.entries.isEmpty {
            ParityEmptyState(
                systemImage: "magnifyingglass",
                title: "Start searching",
                message: "Find your favorite songs, artists or playlists"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recent")
                            .typography(Typography.titleLarge)
                            .foregroundStyle(Color.white)
                        Spacer()
                        Button {
                            viewModel.recentSearchStore.clearAll()
                        } label: {
                            Text("Clear All")
                                .typography(ParityText.bodySmallMedium)
                                .foregroundStyle(ParityColor.greySubtle)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, Dimens.paddingMedium)

                    ForEach(Array(viewModel.recentSearchStore.entries.enumerated()), id: \.element.id) { index, entry in
                        recentSearchRow(entry)
                        if index < viewModel.recentSearchStore.entries.count - 1 {
                            Rectangle()
                                .fill(ParityColor.greyDark)
                                .frame(height: 0.5)
                                .padding(.vertical, Dimens.spacing8)
                        }
                    }
                }
                .padding(Dimens.screenPadding)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder
    private func recentSearchRow(_ entry: RecentSearchEntry) -> some View {
        switch entry {
        case .song(let snapshot):
            SearchSongRow(
                song: snapshot.asSong,
                isPlaying: currentSongID == snapshot.asSong.id,
                onRemove: { viewModel.recentSearchStore.remove(id: entry.id) },
                onTap: { play(song: snapshot.asSong, in: [snapshot.asSong]) }
            )
        case .creator(let creator):
            SearchCreatorRow(
                creator: creator,
                onRemove: { viewModel.recentSearchStore.remove(id: entry.id) },
                onTap: { openCreator(creator) }
            )
        case .playlist(let playlist):
            SearchPlaylistRow(
                playlist: playlist,
                onRemove: { viewModel.recentSearchStore.remove(id: entry.id) },
                onTap: { openPlaylist(playlist) }
            )
        }
    }

    // MARK: - Overview

    /// `_buildOverviewSlivers`: Top Result, then Music / Episodes / Artists /
    /// Playlists each previewing 5 rows. "See all" shows only when the page
    /// holds more than 5 rows or has a next page (`_seeAllVisible`). A tap
    /// queues the section's whole first page, not just the preview.
    @ViewBuilder
    private var overviewContent: some View {
        let preview = SearchViewModel.overviewPreviewCount
        if let topResult = viewModel.topResult {
            sectionHeader("Top Result", filter: nil)
            paddedRow { topResultRow(topResult) }
        }
        if !viewModel.musicPage.items.isEmpty {
            sectionHeader(
                SearchFilter.music.title,
                filter: seeAllVisible(count: viewModel.musicPage.items.count, hasMore: viewModel.musicPage.hasMore) ? .music : nil
            )
            ForEach(Array(viewModel.musicPage.items.prefix(preview))) { song in
                paddedRow { songRow(song, context: viewModel.musicPage.items) }
            }
        }
        if !viewModel.episodePage.items.isEmpty {
            sectionHeader(
                SearchFilter.episode.title,
                filter: seeAllVisible(count: viewModel.episodePage.items.count, hasMore: viewModel.episodePage.hasMore) ? .episode : nil
            )
            ForEach(Array(viewModel.episodePage.items.prefix(preview))) { song in
                paddedRow { songRow(song, context: viewModel.episodePage.items) }
            }
        }
        if !viewModel.creatorPage.items.isEmpty {
            sectionHeader(
                SearchFilter.creator.title,
                filter: seeAllVisible(count: viewModel.creatorPage.items.count, hasMore: viewModel.creatorPage.hasMore) ? .creator : nil
            )
            ForEach(Array(viewModel.creatorPage.items.prefix(preview))) { creator in
                paddedRow { SearchCreatorRow(creator: creator) { openCreator(creator) } }
            }
        }
        if !viewModel.playlistPage.items.isEmpty {
            sectionHeader(
                SearchFilter.playlists.title,
                filter: seeAllVisible(count: viewModel.playlistPage.items.count, hasMore: viewModel.playlistPage.hasMore) ? .playlists : nil
            )
            ForEach(Array(viewModel.playlistPage.items.prefix(preview)), id: \.compositeID) { playlist in
                paddedRow { playlistRow(playlist) }
            }
        }
    }

    private func seeAllVisible(count: Int, hasMore: Bool) -> Bool {
        count > SearchViewModel.overviewPreviewCount || hasMore
    }

    /// Every list item sits in a 16/4 padded box on top of the tile's own
    /// 16/6 padding (`_songSliverList` etc.).
    private func paddedRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Dimens.screenPadding)
            .padding(.vertical, Dimens.spacing4)
    }

    @ViewBuilder
    private func topResultRow(_ item: SearchTopResultItem) -> some View {
        switch item {
        case .song(let song):
            SearchSongRow(song: song, isPlaying: currentSongID == song.id) { play(song: song, in: [song]) }
        case .creator(let creator):
            SearchCreatorRow(creator: creator) { openCreator(creator) }
        case .playlist(let playlist):
            playlistRow(playlist)
        }
    }

    private func songRow(_ song: Song, context: [Song]) -> some View {
        SearchSongRow(song: song, isPlaying: currentSongID == song.id) { play(song: song, in: context) }
    }

    private func playlistRow(_ playlist: SearchPlaylistResult) -> some View {
        SearchPlaylistRow(
            playlist: playlist,
            onMore: playlist.ownerType == .company ? { showMenu(for: playlist) } : nil
        ) { openPlaylist(playlist) }
    }

    /// `_buildSectionHeaderSliver`: 16/12/16/4 inset, `titleMedium` w600 white,
    /// "See all" in `bodySmall` w500 `greySubtle`.
    private func sectionHeader(_ title: String, filter: SearchFilter?) -> some View {
        HStack {
            Text(title)
                .typography(Typography.titleMedium)
                .foregroundStyle(Color.white)
            Spacer()
            if let filter {
                Button {
                    viewModel.selectFilter(filter)
                } label: {
                    Text("See all")
                        .typography(ParityText.bodySmallMedium)
                        .foregroundStyle(ParityColor.greySubtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, Dimens.screenPadding)
        .padding(.top, Dimens.paddingMedium)
        .padding(.trailing, Dimens.screenPadding)
        .padding(.bottom, 4)
    }

    // MARK: - Filtered (single section, paginated)

    @ViewBuilder
    private var filteredContent: some View {
        switch viewModel.activeFilter {
        case .music:
            let items = viewModel.musicPage.items
            ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                paddedRow { songRow(song, context: items) }
                    .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
            }
        case .episode:
            let items = viewModel.episodePage.items
            ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                paddedRow { songRow(song, context: items) }
                    .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
            }
        case .creator:
            let items = viewModel.creatorPage.items
            ForEach(Array(items.enumerated()), id: \.element.id) { index, creator in
                paddedRow { SearchCreatorRow(creator: creator) { openCreator(creator) } }
                    .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
            }
        case .playlists:
            let items = viewModel.playlistPage.items
            ForEach(Array(items.enumerated()), id: \.element.compositeID) { index, playlist in
                paddedRow { playlistRow(playlist) }
                    .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
            }
        case nil:
            EmptyView()
        }
        if viewModel.isLoadingMore {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    ParityShimmerItem()
                }
            }
            .shimmer()
        }
        if shouldShowEndMessage {
            endMessage
        }
    }

    /// `_shouldShowEndMessage`.
    private var shouldShowEndMessage: Bool {
        !viewModel.searchFieldText.isEmpty
            && !viewModel.isInitialLoading
            && !viewModel.isOverview
            && viewModel.hasAnyResults
            && !viewModel.hasMoreData
    }

    /// `_endMessageSliver`.
    private var endMessage: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: Dimens.iconSize))
                .foregroundStyle(ParityColor.greyMuted)
                .padding(Dimens.paddingMedium)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .fill(ParityColor.greyDeep)
                )
            Spacer().frame(height: Dimens.spacing12)
            Text("You've reached the end")
                .typography(ParityText.bodyMediumMedium)
                .foregroundStyle(ParityColor.greySubtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Dimens.spacing24 + 8)
    }

    /// Same idiom as `SectionDetailView.loadMoreIfNeeded`: fire two rows
    /// before the end, not on the very last row.
    private func loadMoreIfNeeded(index: Int, count: Int) {
        guard index >= count - 2 else { return }
        viewModel.loadMore()
    }

    private func showMenu(for playlist: SearchPlaylistResult) {
        menuTarget = .playlist(Playlist(
            id: playlist.id,
            title: playlist.title ?? "",
            description: nil,
            image: playlist.image,
            imageVariants: playlist.imageVariants,
            type: nil,
            visibility: nil,
            language: nil,
            songsCount: nil,
            duration: nil,
            rank: nil,
            owner: .company,
            createdAt: nil,
            updatedAt: nil,
            isSeed: false
        ))
    }

    // MARK: - Actions

    /// First real tap-to-play wiring in the native app: `songs` is always
    /// the relevant section's current item list (not just the tapped song
    /// alone), so the resulting queue can skip forward/back across the rest
    /// of that section — matching what every other surface's future "play
    /// this row" wiring is expected to do (`QueueController.play`'s own doc
    /// comment).
    private func play(song: Song, in songs: [Song]) {
        viewModel.recordSongTap(song)
        let startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        Task {
            await queueController.play(
                songs: songs,
                startIndex: startIndex,
                source: QueueAttribution(playerType: .search, id: nil, title: "Search")
            )
            coordinator.presentPlayer()
        }
    }

    private func openCreator(_ creator: SearchCreatorResult) {
        viewModel.recordCreatorTap(creator)
        coordinator.push(.creatorSongs(creatorID: creator.id, userPlaylistID: nil))
    }

    private func openPlaylist(_ playlist: SearchPlaylistResult) {
        viewModel.recordPlaylistTap(playlist)
        switch playlist.ownerType {
        case .user:
            coordinator.push(.userPlaylistSongs(playlistID: playlist.id))
        case .company:
            // T43: `AppRoute.companyPlaylistSongs` was folded into the
            // unified `.playlistDetail`, which needs a full title/artwork
            // up front (`PlaylistDetailView` renders from a constructed
            // `Playlist` stub, not a fetch-by-id) — `songsCount` has no
            // source here (`SearchPlaylistResult` deliberately omits it,
            // see its own doc comment), and a company playlist has no
            // creator.
            coordinator.push(.playlistDetail(
                playlistID: playlist.id,
                title: playlist.title ?? "",
                image: playlist.image,
                imageVariants: playlist.imageVariants,
                songsCount: nil,
                isCompanyOwned: true,
                creatorID: nil,
                creatorName: nil
            ))
        }
    }
}

/// `_SearchFilterChip`: 16pt horizontal padding, radius 12, 1pt border
/// (white selected / `greyDark`), white fill when selected with a dark-gold
/// 35% glow (blur 8, y 2); label `bodyMedium` w700 black selected, w500
/// `white70` otherwise, +0.2 tracking; 180ms ease-out.
private struct SearchFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    private static let selectedStyle = TypographyToken(size: 14, weight: .bold, lineHeightMultiple: 1.5, tracking: 0.2)
    private static let normalStyle = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1.5, tracking: 0.2)

    var body: some View {
        Button(action: action) {
            Text(label)
                .typography(isSelected ? Self.selectedStyle : Self.normalStyle)
                .foregroundStyle(isSelected ? Color.black : ParityColor.white70)
                .padding(.horizontal, Dimens.spacing16)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                        .shadow(color: isSelected ? ParityColor.darkGold.opacity(0.35) : Color.clear, radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .stroke(isSelected ? Color.white : ParityColor.greyDark, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}
