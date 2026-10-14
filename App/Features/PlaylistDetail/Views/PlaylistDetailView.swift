import SwiftUI

/// T29 — "album songs"/"company playlist songs", unified: a header (cover,
/// title, song count) over a plain list of `CreatorSongRow`s, paginated the
/// same `hasMore`-driven way as Home's rails. Structural-only, same "no
/// pixel-parity requirement" scope note as Home's own views (T28) — Dart's
/// `PlaylistSongPage`/`CompanyPlaylistSongsPage` each have their own bespoke
/// header treatment this doesn't attempt to reproduce.
struct PlaylistDetailView: View {
    @State private var viewModel: PlaylistDetailViewModel
    @State private var menuTarget: ContentMenuTarget?

    @Environment(\.appTheme) private var theme

    init(playlist: Playlist) {
        _viewModel = State(initialValue: PlaylistDetailViewModel(playlist: playlist))
    }

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: viewModel.playlist.image,
            variant: .lg,
            allowedVariants: viewModel.playlist.imageVariants
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                header
                content
            }
            .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .contentMenu(target: $menuTarget)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ArtworkView(url: resolvedArtwork, width: 160, height: 160, cornerRadius: Radius.lg)
            Text(viewModel.playlist.title)
                .typography(Typography.titleLarge)
                .foregroundStyle(theme.color(.textPrimary))
            if let songsCount = viewModel.playlist.songsCount {
                Text("\(songsCount) songs")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Spacing.md)
    }

    /// Gated to company-owned playlists only — `end_points.dart` has no
    /// bare (non-company) creator-playlist share route (`Endpoint+Share.swift`'s
    /// own doc comment), and `UserPlaylistDetailView`'s own Share affordance
    /// is T45's already-made scope cut.
    /// Save to library (`AddToLibraryButton`) and the container menu
    /// (`showContentMenu`: queue, share, library) — the share button that
    /// used to live here is now one of that menu's rows.
    private var actions: some View {
        HStack(spacing: Spacing.lg) {
            AddToLibraryButton(
                type: viewModel.playlist.libraryItemType,
                itemID: viewModel.playlist.id,
                title: viewModel.playlist.title
            )
            Button { menuTarget = .playlist(viewModel.playlist) } label: {
                theme.icon(.more)
                    .font(.system(size: 22))
                    .foregroundStyle(theme.color(.textPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .empty:
            EmptyStateView(title: "No songs yet")
        case .failed:
            ErrorStateView(
                title: "Couldn't load this playlist",
                onRetry: { Task { await viewModel.refresh() } }
            )
        case .loaded(let page):
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, song in
                    CreatorSongRow(song: song)
                        .padding(.horizontal, Spacing.md)
                        .onAppear {
                            guard index >= page.items.count - 2 else { return }
                            viewModel.loadMore()
                        }
                }
            }
        }
    }
}
