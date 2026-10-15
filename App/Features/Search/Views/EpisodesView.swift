import SwiftUI

/// Ports `EpisodesPage` (`lib/views/search/episodes.dart`, route `/episodes`):
/// bold "Podcasts" title, the tap-through `SearchWidgetUi` bar (pushes
/// `.contentSearch`), a 12pt gap, then the same 2-column `CategoryUI` grid as
/// Search (`3/1.75`, 16pt row spacing) over genres of type `podcasts`, with a
/// 108pt bottom bar. Dart shows no loading/empty/error state.
///
/// NOTE: `AppShellView` still routes `.episodes` to a placeholder; it should
/// dispatch to `EpisodesView()`.
struct EpisodesView: View {
    @State private var viewModel = EpisodesViewModel()

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 0) {
            // App-bar `bottom`: the search bar stays pinned under the title.
            ParityFakeSearchBar {
                coordinator.push(.contentSearch(userPlaylistID: nil, tags: [], checkedContent: [], isSelect: false))
            }
            .padding(.horizontal, Dimens.screenPaddingAll)
            .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 12)

                    content

                    Color.clear.frame(height: 108)
                }
            }
        }
        .background(Color.black)
        .parityNavTitle {
            Text("Podcasts")
                .font(AccountParity.titleLarge)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
        }
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        let genres = viewModel.displayedGenres
        if genres.isEmpty, viewModel.isLoading {
            ParitySpinner(fills: true)
        } else if let error = viewModel.loadError, genres.isEmpty {
            ErrorStateView(title: "Couldn't load podcasts", message: error) {
                Task { await viewModel.load() }
            }
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
