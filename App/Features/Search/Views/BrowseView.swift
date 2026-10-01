import SwiftUI

/// Ports `SearchPage` (`lib/views/search/search_page.dart`) — the Search
/// tab's root: a tap-through fake search bar (pushes `.contentSearch`,
/// matching `SearchWidgetUi`'s `onTap`), a Music/Episode toggle
/// (`SongTypeTopNavigationButton`, reusing `AppChip(stretches: true)`), and a
/// 2-column genre grid (`CategoryUI`).
///
/// No collapsing `SliverAppBar` parallax here — same "D10 doesn't apply to
/// Search" exemption `ContentSearchView`/`CreatorProfileView` already rely
/// on; the tab root's own `.navigationTitle` (`AppShellView.TabRootView`)
/// already supplies the "Search" title Dart's `SliverAppBar` shows.
struct BrowseView: View {
    @State private var viewModel = BrowseViewModel()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    private static let gridSpacing: CGFloat = Spacing.md

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                fakeSearchBar
                    .padding(.horizontal, Spacing.md)

                contentTypeToggle
                    .padding(.horizontal, Spacing.md)

                genreGrid
            }
            .padding(.vertical, Spacing.sm)
        }
        .background(theme.color(.backgroundPrimary))
        .task { await viewModel.onAppear() }
    }

    /// `SearchWidgetUi`, tapped rather than typed into: same chrome as
    /// `SearchTextField` (`Radius.md`/`surfaceInput`/`Spacing.inputHeight`),
    /// but a `Button`, not a live `TextField` — this bar is never itself
    /// editable, only a navigation trigger to `ContentSearchView`.
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

    private var contentTypeToggle: some View {
        HStack(spacing: Spacing.sm) {
            AppChip(title: "Music", isSelected: viewModel.selectedType == .music, stretches: true) {
                viewModel.selectedType = .music
            }
            AppChip(title: "Episode", isSelected: viewModel.selectedType == .episode, stretches: true) {
                viewModel.selectedType = .episode
            }
        }
    }

    @ViewBuilder
    private var genreGrid: some View {
        let genres = viewModel.displayedGenres
        if genres.isEmpty, viewModel.isLoading {
            LoadingStateView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let error = viewModel.loadError, genres.isEmpty {
            ErrorStateView(title: "Couldn't load genres", message: error) {
                Task { await viewModel.loadGenres() }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if genres.isEmpty {
            EmptyStateView(title: "No genres yet")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Self.gridSpacing), GridItem(.flexible())],
                spacing: Self.gridSpacing
            ) {
                ForEach(genres) { genre in
                    GenreGridCard(genre: genre) {
                        coordinator.push(.genreSongs(
                            genreID: genre.genreId,
                            genreName: genre.name,
                            genreImage: genre.image,
                            genreImageVariants: genre.imageVariants
                        ))
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }
}

/// Ports `CategoryUI` (`lib/widgets/song/category_ui.dart`): the card
/// hardcodes `width = 188, height = 133` internally regardless of its own
/// `LayoutBuilder` constraints (confirmed by direct read — the parent
/// `SliverGrid`'s `childAspectRatio` is decorative there, not the card's
/// real rendered shape), so this replicates that fixed size directly rather
/// than building a responsive `GeometryReader` card that Dart's own screen
/// doesn't actually have. The bottom name bar is `width - 16`, not the full
/// card width, leaving an 8pt strip of bare artwork visible at the trailing
/// edge — also a literal match, not a simplification.
private struct GenreGridCard: View {
    let genre: Genre
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    private static let cardWidth: CGFloat = 188
    private static let cardHeight: CGFloat = 133
    private static let textBarWidth: CGFloat = cardWidth - 16

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(
                    url: ArtworkURLResolver().resolve(path: genre.image, variant: .md, allowedVariants: genre.imageVariants),
                    width: Self.cardWidth,
                    height: Self.cardHeight,
                    cornerRadius: 0
                )
                Text(genre.name ?? "")
                    .typography(Typography.titleMedium)
                    .foregroundStyle(theme.color(.textInverse))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(Spacing.xs)
                    .frame(width: Self.textBarWidth, alignment: .leading)
                    .background(Color.black.opacity(0.6))
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
