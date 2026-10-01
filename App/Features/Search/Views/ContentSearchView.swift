import SwiftUI

/// T40/T41 — ports `content_search_page.dart` + `SearchBloc`. Three
/// mutually-exclusive bodies, matching Dart's own top-level branch there:
/// - empty query → recent searches (or the first-run empty state)
/// - a query, `activeFilter == nil` → overview (top result + a 5-item
///   preview per section)
/// - a query, `activeFilter` set → one section's full paginated list
///
/// No `ErrorStateView` anywhere here: `SearchViewModel` doesn't expose an
/// observable error at all (see its own doc comment) — a failed fetch just
/// leaves whatever was already on screen, matching Dart's real behavior.
struct ContentSearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    private var trimmedQuery: String {
        viewModel.searchFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchTextField(
                text: Binding(
                    get: { viewModel.searchFieldText },
                    set: { viewModel.queryChanged($0) }
                ),
                placeholder: "Search music, episodes, artists, playlists",
                onClear: { viewModel.clearButtonTapped() }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            filterChips

            resultsBody
        }
        .background(theme.color(.backgroundPrimary))
    }

    @ViewBuilder
    private var filterChips: some View {
        if !trimmedQuery.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    AppChip(title: "All", isSelected: viewModel.activeFilter == nil) {
                        viewModel.selectFilter(nil)
                    }
                    ForEach(SearchFilter.allCases, id: \.rawValue) { filter in
                        AppChip(title: filter.title, isSelected: viewModel.activeFilter == filter) {
                            viewModel.selectFilter(filter)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if trimmedQuery.isEmpty {
            recentSearchesSection
        } else if viewModel.isBusy {
            ScrollView { searchShimmer }
        } else if !viewModel.hasAnyResults {
            EmptyStateView(icon: .search, title: "No results found", message: "Try a different search term.")
                .frame(maxHeight: .infinity)
        } else if viewModel.isOverview {
            overviewContent
        } else {
            filteredContent
        }
    }

    // MARK: - Recent searches

    @ViewBuilder
    private var recentSearchesSection: some View {
        if viewModel.recentSearchStore.entries.isEmpty {
            EmptyStateView(
                icon: .search,
                title: "Search Hallelujah",
                message: "Find music, episodes, artists, and playlists."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        theme.icon(.recentSearch)
                            .foregroundStyle(theme.color(.textSecondary))
                        Text("Recent Searches")
                            .typography(Typography.titleSmall)
                            .foregroundStyle(theme.color(.textPrimary))
                        Spacer()
                        Button {
                            viewModel.recentSearchStore.clearAll()
                        } label: {
                            Text("Clear All")
                                .typography(Typography.labelLarge)
                                .foregroundStyle(theme.color(.textSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, Spacing.sm)

                    ForEach(viewModel.recentSearchStore.entries) { entry in
                        recentSearchRow(entry)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
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

    @ViewBuilder
    private var overviewContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                // Each section is its own tight `Spacing.sm` group (header
                // hugging its own rows), with `Spacing.lg` only between
                // groups — the same two-tier rhythm `HomeSectionRailView`
                // uses (and `searchShimmer` below already mirrors), rather
                // than one flat spacing that can't tell "within a section"
                // from "between sections" apart.
                if let topResult = viewModel.topResult {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        sectionHeader("Top Result", filter: nil)
                        topResultRow(topResult)
                    }
                }
                if !viewModel.musicPage.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        sectionHeader(SearchFilter.music.title, filter: .music)
                        ForEach(Array(viewModel.musicPage.items.prefix(SearchViewModel.overviewPreviewCount))) { song in
                            SearchSongRow(song: song) {
                                play(song: song, in: Array(viewModel.musicPage.items.prefix(SearchViewModel.overviewPreviewCount)))
                            }
                        }
                    }
                }
                if !viewModel.episodePage.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        sectionHeader(SearchFilter.episode.title, filter: .episode)
                        ForEach(Array(viewModel.episodePage.items.prefix(SearchViewModel.overviewPreviewCount))) { song in
                            SearchSongRow(song: song) {
                                play(song: song, in: Array(viewModel.episodePage.items.prefix(SearchViewModel.overviewPreviewCount)))
                            }
                        }
                    }
                }
                if !viewModel.creatorPage.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        sectionHeader(SearchFilter.creator.title, filter: .creator)
                        ForEach(Array(viewModel.creatorPage.items.prefix(SearchViewModel.overviewPreviewCount))) { creator in
                            SearchCreatorRow(creator: creator) { openCreator(creator) }
                        }
                    }
                }
                if !viewModel.playlistPage.items.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        sectionHeader(SearchFilter.playlists.title, filter: .playlists)
                        ForEach(
                            Array(viewModel.playlistPage.items.prefix(SearchViewModel.overviewPreviewCount)),
                            id: \.compositeID
                        ) { playlist in
                            SearchPlaylistRow(playlist: playlist) { openPlaylist(playlist) }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func topResultRow(_ item: SearchTopResultItem) -> some View {
        switch item {
        case .song(let song):
            SearchSongRow(song: song) { play(song: song, in: [song]) }
        case .creator(let creator):
            SearchCreatorRow(creator: creator) { openCreator(creator) }
        case .playlist(let playlist):
            SearchPlaylistRow(playlist: playlist) { openPlaylist(playlist) }
        }
    }

    private func sectionHeader(_ title: String, filter: SearchFilter?) -> some View {
        HStack {
            Text(title)
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
            Spacer()
            if let filter {
                Button {
                    viewModel.selectFilter(filter)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("See all")
                            .typography(Typography.labelLarge)
                        theme.icon(.chevronForward)
                    }
                    .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Filtered (single section, paginated)

    @ViewBuilder
    private var filteredContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch viewModel.activeFilter {
                case .music:
                    let items = viewModel.musicPage.items
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                        SearchSongRow(song: song) { play(song: song, in: items) }
                            .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
                    }
                case .episode:
                    let items = viewModel.episodePage.items
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                        SearchSongRow(song: song) { play(song: song, in: items) }
                            .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
                    }
                case .creator:
                    let items = viewModel.creatorPage.items
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, creator in
                        SearchCreatorRow(creator: creator) { openCreator(creator) }
                            .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
                    }
                case .playlists:
                    let items = viewModel.playlistPage.items
                    ForEach(Array(items.enumerated()), id: \.element.compositeID) { index, playlist in
                        SearchPlaylistRow(playlist: playlist) { openPlaylist(playlist) }
                            .onAppear { loadMoreIfNeeded(index: index, count: items.count) }
                    }
                case nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Same idiom as `SectionDetailView.loadMoreIfNeeded`: fire two rows
    /// before the end, not on the very last row.
    private func loadMoreIfNeeded(index: Int, count: Int) {
        guard index >= count - 2 else { return }
        viewModel.loadMore()
    }

    // MARK: - Shimmer

    /// One `.shimmer()` wrapping the whole composed skeleton — never one per
    /// row — matching `Shimmer.swift`'s explicit cost rule.
    private var searchShimmer: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SkeletonBox(width: 120, height: 20)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: Spacing.md) {
                            SkeletonBox(width: SearchSongRow.thumbnailSize, height: SearchSongRow.thumbnailSize)
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                SkeletonBox(width: 180, height: 16)
                                SkeletonBox(width: 120, height: 14)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .shimmer()
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
