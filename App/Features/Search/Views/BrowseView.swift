import SwiftUI

/// Ports `SearchPage` (`lib/views/search/search_page.dart`): pinned "Search"
/// title (supplied by the tab root's nav title), the tap-through
/// `SearchWidgetUi` bar (70pt tall, pushes `.contentSearch`), a Music/Episode
/// `SongTypeTopNavigationButton` pair (36pt, 16pt gap, 16pt side inset), and a
/// 2-column `CategoryUI` grid (`childAspectRatio 3/1.75`, 16pt row spacing,
/// 0 column spacing, 8pt side padding). Section gaps are `Dimens.verticalSpacing`
/// (12). Dart renders no loading/empty/error state here (an empty Realm query
/// is just an empty grid); the native fetch needs a spinner/retry, which is the
/// only addition.
struct BrowseView: View {
    @State private var viewModel = BrowseViewModel()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // `SliverPersistentHeader(pinned: true)`: the bar stays under the
            // title while the rest scrolls.
            ParityFakeSearchBar {
                coordinator.push(.contentSearch(userPlaylistID: nil, tags: [], checkedContent: [], isSelect: false))
            }
            .padding(.horizontal, Dimens.screenPaddingAll)
            .frame(maxWidth: .infinity)
            .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: Dimens.verticalSpacing)

                    contentTypeToggle
                        .padding(.horizontal, Dimens.screenPaddingAll + 8)

                    Spacer().frame(height: Dimens.verticalSpacing)

                    genreGrid

                    // `Ios26BottomSpacing(multiply: 3)` over the floating dock.
                    Color.clear.frame(height: 16)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.black)
        .task { await viewModel.onAppear() }
    }

    private var contentTypeToggle: some View {
        HStack(spacing: Dimens.horizontalSpacing) {
            ParityTypeButton(title: "Music", isSelected: viewModel.selectedType == .music) {
                viewModel.selectedType = .music
            }
            ParityTypeButton(title: "Episode", isSelected: viewModel.selectedType == .episode) {
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
            ErrorStateView(title: String(localized: "Couldn't load genres"), message: error) {
                Task { await viewModel.loadGenres() }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
                spacing: 16
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
            .padding(.horizontal, Dimens.screenPaddingAll)
        }
    }
}

/// Ports `CategoryUI` (`lib/widgets/song/category_ui.dart`). The grid cell is
/// `(width - 16) / 2` wide by `cellWidth * 1.75 / 3` tall (the delegate's tight
/// constraints win over the widget's literal `188`), inset 8pt each side. The
/// image fills the card (radius 8); the name bar sits bottom-left over it:
/// black 60%, 4pt padding, bottom corners radius 8, `titleMedium`, one line.
struct GenreGridCard: View {
    let genre: Genre
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let cardWidth = max(geo.size.width - 16, 0)
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(
                        url: ArtworkURLResolver().resolve(path: genre.image, variant: .md, allowedVariants: genre.imageVariants),
                        width: cardWidth,
                        height: geo.size.height,
                        cornerRadius: 8
                    )
                    Text(genre.name ?? "Unknown")
                        .typography(Typography.titleMedium)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(Dimens.spacing4)
                        .frame(width: cardWidth, alignment: .leading)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 8,
                                bottomTrailingRadius: 8,
                                topTrailingRadius: 0,
                                style: .continuous
                            )
                            .fill(Color.black.opacity(0.6))
                        )
                }
                .frame(width: cardWidth, height: geo.size.height)
                .padding(.horizontal, 8)
            }
            .aspectRatio(3.0 / 1.75, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
