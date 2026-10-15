import SwiftUI

/// Ports `GenreSearchPage` (`lib/views/search/genre_search_page.dart`, route
/// `/genre_search`): a "Search Music" title, a pinned inline search field
/// ("Search songs, genres...", 1D1D1D, radius 8) and, below, either the
/// "Browse Genres" grid (empty field) or a music-only result list
/// ("No songs found" / "Try searching with different keywords" when empty).
/// The query is sent immediately with the `music` filter locked.
///
/// Not ported: the microphone button (needs speech recognition).
/// NOTE: `AppShellView` still routes `.genreSearch` to a placeholder; it
/// should dispatch to `GenreSearchView()`.
struct GenreSearchView: View {
    @State private var viewModel = SearchViewModel(lockedFilter: .music)
    @State private var browse = BrowseViewModel()
    @State private var queueController: QueueController = DependencyContainer.current.resolve()
    @FocusState private var isFocused: Bool
    @State private var isListening = false

    @Environment(AppNavigationCoordinator.self) private var coordinator

    private var query: String { viewModel.searchFieldText }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned `SliverPersistentHeader` under the app bar.
            searchBar
                .background(Color.black)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: Dimens.verticalSpacing)
                    if query.isEmpty {
                        genresSection
                    } else {
                        resultsSection
                    }
                    Color.clear.frame(height: 16)
                }
            }
        }
        .background(Color.black)
        .parityNavTitle("Search Music", leading: true)
        .scrollDismissesKeyboard(.immediately)
        .task { await browse.onAppear() }
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .padding(Dimens.spacing8)
            TextField(
                "",
                text: Binding(
                    get: { viewModel.searchFieldText },
                    set: { viewModel.queryChanged($0) }
                ),
                prompt: Text(isListening ? "Listening\u{2026}" : "Search songs, genres...").foregroundColor(ParityColor.grey.opacity(0.7))
            )
            .typography(Typography.bodyMedium)
            .foregroundStyle(Color.white)
            .focused($isFocused)
            .autocorrectionDisabled()
            VoiceSearchButton(
                onResult: { text, _ in viewModel.queryChanged(text) },
                onListeningChanged: { isListening = $0 },
                size: 20
            )
            .frame(width: 32, height: 32)
            if !query.isEmpty {
                Button { viewModel.clearButtonTapped() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(ParityColor.grey.opacity(0.7))
                        .padding(Dimens.spacing8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Dimens.spacing8)
        .glassRounded(Dimens.cornerRadius)
        .padding(Dimens.spacing8)
        .padding(.horizontal, Dimens.screenPaddingAll)
    }

    // MARK: - Genres

    @ViewBuilder
    private var genresSection: some View {
        Text("Browse Genres")
            .typography(Typography.titleMedium)
            .foregroundStyle(Color.white)
            .padding(.horizontal, Dimens.screenPaddingAll)
            .padding(.vertical, Dimens.spacing8)
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
            spacing: 16
        ) {
            ForEach(browse.allGenres.filter { $0.type == "music" && $0.image != "" }) { genre in
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

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if viewModel.isInitialLoading || viewModel.isSearchPending {
            ParityShimmerList()
        } else if viewModel.musicPage.items.isEmpty {
            VStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundStyle(ParityColor.grey.opacity(0.5))
                Spacer().frame(height: 16)
                Text("No songs found")
                    .typography(Typography.titleMedium)
                    .foregroundStyle(ParityColor.grey)
                Spacer().frame(height: 8)
                Text("Try searching with different keywords")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(ParityColor.grey.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            let items = viewModel.musicPage.items
            LazyVStack(spacing: 0) {
                ForEach(items) { song in
                    SearchSongRow(song: song, isPlaying: queueController.queue?.currentSong?.id == song.id) {
                        play(song: song, in: items)
                    }
                    .padding(.horizontal, Dimens.screenPadding)
                    .padding(.vertical, Dimens.spacing4)
                }
            }
        }
    }

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
}
