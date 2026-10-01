import SwiftUI

/// Ports `LibraryPage` (`lib/views/library/library.dart`): a "Create"
/// toolbar action, a tap-through fake search bar (`SearchWidgetUi`), a
/// 3-way All/Music/Podcast filter row (`SongTypeTopNavigationButton`), four
/// conditional quick-link tiles (`LibraryUi`), and the merged paginated
/// playlist list (`LibraryListItem`).
///
/// No "recents" section — despite this task's own roadmap entry mentioning
/// one, the real Dart source (`library.dart`, read directly) has no such
/// section anywhere on this screen; the roadmap's description is a
/// speculative a-priori guess this intentionally doesn't follow. D10
/// (splash/auth pixel parity) doesn't apply here either — Library gets the
/// same "structural port, native Liquid Glass" treatment Home/Search
/// already got (T28/T42).
struct LibraryHomeView: View {
    @State private var viewModel = LibraryViewModel()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                fakeSearchBar
                    .padding(.horizontal, Spacing.md)

                filterRow
                    .padding(.horizontal, Spacing.md)

                quickLinks
                    .padding(.horizontal, Spacing.md)

                itemList
            }
            .padding(.vertical, Spacing.sm)
        }
        .background(theme.color(.backgroundPrimary))
        .refreshable { await viewModel.refresh() }
        // Dart's `onTap` re-dispatches both load events even when tapping
        // the already-selected chip, forcing a wasted reload; `.task(id:)`
        // only re-fires on an actual value change, so a repeat tap here is a
        // no-op instead — a deliberate, harmless divergence (same data,
        // nothing to re-render), not a gap to close.
        .task(id: viewModel.filter) { await viewModel.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create") {
                    coordinator.push(.createPlaylist(userPlaylistID: nil, songType: nil, songID: nil))
                }
            }
        }
    }

    // MARK: - Search bar

    /// `SearchWidgetUi`, tapped rather than typed into — same pattern as
    /// `BrowseView.fakeSearchBar`; no shared component to reuse (none
    /// exists anywhere in this codebase yet).
    private var fakeSearchBar: some View {
        Button {
            coordinator.push(.contentSearch(userPlaylistID: nil, tags: [], checkedContent: [], isSelect: false))
        } label: {
            HStack(spacing: Spacing.sm) {
                theme.icon(.search)
                    .foregroundStyle(theme.color(.textTertiary))
                Text("Search music, episodes, artists, playlists")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textTertiary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: Spacing.inputHeight)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(theme.color(.surfaceInput))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter row

    /// `SongTypeTopNavigationButton` × 3 (`library.dart`) — unlike
    /// `BrowseView`'s Music/Episode-only pair, Library's own row has a
    /// third "All" option (`SongType.all`), confirmed directly against the
    /// Dart source.
    private var filterRow: some View {
        HStack(spacing: Spacing.sm) {
            AppChip(title: "All", isSelected: viewModel.filter == .all, stretches: true) {
                viewModel.filter = .all
            }
            AppChip(title: "Music", isSelected: viewModel.filter == .music, stretches: true) {
                viewModel.filter = .music
            }
            AppChip(title: "Podcast", isSelected: viewModel.filter == .episode, stretches: true) {
                viewModel.filter = .episode
            }
        }
    }

    // MARK: - Quick links

    /// `LibraryUi` (`library_item_ui.dart`): Downloads only for `.all`,
    /// Liked Music for `.all`/`.music`, Liked Episodes for `.all`/
    /// `.episode`, Liked Artists always — exact visibility rules confirmed
    /// directly against that widget's source.
    ///
    /// Downloads has no network count to wait on (T46 doesn't exist yet, see
    /// below), so it's never gated by `isLoadingCounts` — matching Dart,
    /// whose own `_LibraryItemShimmer` only ever covers the liked-* trio.
    /// The other three swap to `quickLinkSkeletonRow` while `counts` is
    /// still nil and a fetch is in flight, instead of flashing a bare `0`.
    @ViewBuilder
    private var quickLinks: some View {
        VStack(spacing: 0) {
            if viewModel.filter == .all {
                // No download engine exists yet (T46) — this app has
                // nothing on-device to count, unlike Dart's local Realm
                // tally, so this is an honest `0` rather than a fetched
                // number.
                LibraryQuickLinkRow(icon: .download, title: "Downloads", count: 0) {
                    coordinator.push(.downloads(type: viewModel.filter.rawValue))
                }
            }

            if viewModel.isLoadingCounts, viewModel.counts == nil {
                countsSkeleton
            } else {
                if viewModel.filter == .all || viewModel.filter == .music {
                    LibraryQuickLinkRow(
                        icon: .favoriteFilled,
                        title: "Liked Music",
                        count: viewModel.counts?.likedMusic ?? 0
                    ) {
                        coordinator.push(.favouriteSongs(type: "music", label: "Liked Music", asset: "liked_musics"))
                    }
                }
                if viewModel.filter == .all || viewModel.filter == .episode {
                    LibraryQuickLinkRow(
                        icon: .favoriteFilled,
                        title: "Liked Episodes",
                        count: viewModel.counts?.likedEpisodes ?? 0
                    ) {
                        coordinator.push(.favouriteSongs(type: "episode", label: "Liked Episodes", asset: "liked_episode"))
                    }
                }
                LibraryQuickLinkRow(
                    icon: .artists,
                    title: "Liked Artists",
                    count: viewModel.counts?.likedArtists ?? 0
                ) {
                    coordinator.push(.favouriteArtists(songType: viewModel.filter.rawValue))
                }
            }
        }
    }

    /// One row per tile that would otherwise render this pass, gated by the
    /// same filter rules as the real rows above — mirrors Dart's per-tile
    /// `_LibraryItemShimmer`. Wrapped in a single `.shimmer()` around the
    /// whole stack rather than one per row: `Shimmer.swift`'s own header
    /// comment documents this as a hard cost rule ("ONE Shimmer PER
    /// SECTION, never per card"), since `.shimmer()` owns an animation that
    /// ticks every frame.
    private var countsSkeleton: some View {
        VStack(spacing: 0) {
            if viewModel.filter == .all || viewModel.filter == .music {
                quickLinkSkeletonRow
            }
            if viewModel.filter == .all || viewModel.filter == .episode {
                quickLinkSkeletonRow
            }
            quickLinkSkeletonRow
        }
        .shimmer()
    }

    private var quickLinkSkeletonRow: some View {
        HStack(spacing: Spacing.md) {
            SkeletonBox(width: 44, height: 44, radius: Radius.sm)
            SkeletonBox(width: 120, height: 16)
            Spacer(minLength: 0)
            SkeletonBox(width: 28, height: 14)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Merged list

    private var itemList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.items) { entry in
                LibraryEntryRow(entry: entry) { open(entry) }
                    .padding(.horizontal, Spacing.md)
                    .task { await viewModel.loadMoreItemsIfNeeded(currentItem: entry) }
            }
            if viewModel.isLoadingItems {
                LoadingStateView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.hasLoadedOnce, viewModel.items.isEmpty {
                EmptyStateView(title: "No saved playlists yet")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
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
        case let .userPlaylist(id, _, _, _, _, _):
            coordinator.push(.userPlaylistSongs(playlistID: id))
        }
    }
}
