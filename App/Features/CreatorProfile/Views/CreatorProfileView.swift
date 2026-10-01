import SwiftUI

/// Ports `CreatorSongsPage` (`lib/views/library/creator_songs_page.dart`),
/// T30's "Creator page, their songs, follow/favourite": a header (artwork,
/// name, follower count, follow button) and Songs/Albums/Podcasts/Seasons
/// tabs, each an independently-paginated list.
///
/// Left out of this pass, all deliberate scope cuts:
/// - The collapsing `SliverAppBar` hero-image parallax and the "⋮" creator
///   menu itself (`showCreatorMenu`) — cosmetic/secondary. A plain header +
///   `ScrollView` carries the same information. Share (T68) is wired as its
///   own `shareButton` rather than reviving that menu just to hold one item;
///   report has no native endpoint wiring and stays out.
/// - The shuffle/play-all row next to the tab bar — needs the playback
///   engine (T31+), which doesn't exist yet.
/// - Tapping a row: T31+ (playback) and T29 (playlist detail screens) own
///   what a tap should actually do; rows here are display-only for now.
struct CreatorProfileView: View {
    @State private var viewModel: CreatorProfileViewModel
    @State private var isSharePresented = false
    @Environment(\.appTheme) private var theme

    init(creatorId: String) {
        _viewModel = State(initialValue: CreatorProfileViewModel(creatorId: creatorId))
    }

    var body: some View {
        ScrollView {
            if let creator = viewModel.creator {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header(for: creator)
                    if !viewModel.tabs.isEmpty {
                        tabBar
                        tabContent
                    }
                }
                .padding(.bottom, Spacing.xl)
            } else if viewModel.isLoadingCreator {
                LoadingStateView()
                    .frame(maxWidth: .infinity, minHeight: 320)
            } else if let error = viewModel.loadError {
                ErrorStateView(title: "Couldn't load this creator", message: error) {
                    Task { await viewModel.loadCreator() }
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .background(theme.color(.backgroundPrimary))
        .task { await viewModel.onAppear() }
        .appSheet(isPresented: $isSharePresented) {
            if let creator = viewModel.creator {
                ShareSheetView(
                    target: .creator(id: creator.id),
                    title: creator.name ?? "",
                    subtitle: nil,
                    artworkURL: ArtworkURLResolver().resolve(
                        path: creator.image,
                        variant: .lg,
                        allowedVariants: creator.imageVariants
                    )
                )
            }
        }
    }

    // MARK: - Header

    /// `ArtworkView` needs a concrete pixel size up front for its own
    /// downsampling (`maxPixelSize = max(width, height) * displayScale`), so
    /// this reads the container's actual width via `GeometryReader` rather
    /// than a `UIScreen.main` guess — the latter also predates multi-window
    /// iPadOS, which this reader isn't tied to.
    private static let heroHeight: CGFloat = 280

    private func header(for creator: Creator) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            GeometryReader { proxy in
                ArtworkView(
                    url: ArtworkURLResolver().resolve(path: creator.image, variant: .lg, allowedVariants: creator.imageVariants),
                    width: proxy.size.width,
                    height: Self.heroHeight,
                    cornerRadius: 0,
                    contentMode: .fill
                )
            }
            .frame(height: Self.heroHeight)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(creator.name ?? "")
                    .typography(Typography.headlineMedium)
                    .foregroundStyle(theme.color(.textPrimary))

                HStack(spacing: Spacing.sm) {
                    Text("\(creator.followersCount ?? 0) Followers")
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textSecondary))

                    AppChip(
                        title: creator.isFollowing == true ? "Following" : "Follow",
                        isSelected: creator.isFollowing == true,
                        enabled: !viewModel.isTogglingFollow
                    ) {
                        Task { await viewModel.toggleFollow() }
                    }

                    Spacer()

                    shareButton
                }

                if let bio = creator.bio, !bio.isEmpty {
                    Text(bio)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textSecondary))
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private var shareButton: some View {
        Button {
            isSharePresented = true
        } label: {
            theme.icon(.share)
                .foregroundStyle(theme.color(.textSecondary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.tabs, id: \.self) { tab in
                    AppChip(title: tab.title, isSelected: viewModel.selectedTab == tab) {
                        viewModel.selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .songs(let type):
            songsList(type: type)
        case .playlists(let type):
            playlistsList(type: type)
        case nil:
            EmptyView()
        }
    }

    private func songsList(type: HomeContentType) -> some View {
        let songs = viewModel.songs(for: type)
        return VStack(spacing: 0) {
            if songs.isEmpty, viewModel.isLoadingSongs(for: type) {
                LoadingStateView().frame(maxWidth: .infinity, minHeight: 160)
            } else if songs.isEmpty {
                EmptyStateView(title: "No songs yet").frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(songs) { song in
                    CreatorSongRow(song: song)
                        .padding(.horizontal, Spacing.md)
                        .task { await viewModel.loadMoreSongsIfNeeded(type: type, currentItem: song) }
                }
                if viewModel.isLoadingSongs(for: type) {
                    LoadingStateView().frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
        .task(id: type) { await viewModel.loadSongsIfNeeded(type: type) }
    }

    private func playlistsList(type: HomeContentType) -> some View {
        let playlists = viewModel.playlists(for: type)
        return VStack(spacing: 0) {
            if playlists.isEmpty, viewModel.isLoadingPlaylists(for: type) {
                LoadingStateView().frame(maxWidth: .infinity, minHeight: 160)
            } else if playlists.isEmpty {
                EmptyStateView(title: "Nothing here yet").frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(playlists) { playlist in
                    CreatorPlaylistRow(playlist: playlist, contentType: type)
                        .padding(.horizontal, Spacing.md)
                        .task { await viewModel.loadMorePlaylistsIfNeeded(type: type, currentItem: playlist) }
                }
                if viewModel.isLoadingPlaylists(for: type) {
                    LoadingStateView().frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
        .task(id: type) { await viewModel.loadPlaylistsIfNeeded(type: type) }
    }
}
