import SwiftUI

/// Ports `FavouriteArtistPage` (`lib/views/library/grid_artists_favorite.dart`):
/// app bar "Favourite Artist" with a trailing "+" (opens `CreatorGridPage`),
/// a `CreatorGridItem` grid (max 100pt cells, 12pt spacing, 0.75 aspect;
/// 16pt side / 8pt top padding), pull-to-refresh, a spinner while the first
/// page loads and "No favourite artists." when empty. Cells open the artist
/// page (`CreatorSongsPage`).
struct FavouriteArtistsView: View {
    @State private var viewModel: FavouriteArtistsViewModel
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private let songType: String

    init(songType: String) {
        self.songType = songType
        _viewModel = State(initialValue: FavouriteArtistsViewModel(songType: songType))
    }

    var body: some View {
        content
            .background(Color.black)
            .parityNavTitle("Favourite Artist")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        coordinator.push(.creatorGrid(title: "Favourite Artist", songType: songType))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add artists")
                }
            }
            .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.creators.isEmpty {
            if viewModel.isLoadingCreators || !viewModel.hasLoadedOnce {
                ParitySpinner(fills: true)
                    .frame(maxHeight: .infinity)
            } else {
                ParityEmptyText(text: "No favourite artists.")
                    .frame(maxHeight: .infinity)
            }
        } else {
            ScrollView {
                CreatorMaxExtentGrid(items: viewModel.creators) { creator in
                    CreatorGridCell(creator: creator) {
                        coordinator.push(.creatorSongs(creatorID: creator.creatorId, userPlaylistID: nil))
                    }
                    .task { await viewModel.loadMoreCreatorsIfNeeded(currentItem: creator) }
                }
                .padding(.horizontal, Dimens.screenPaddingAll * 2)
                .padding(.top, Dimens.screenPaddingAll)
                if viewModel.isLoadingCreators {
                    ParitySpinner()
                }
                Color.clear.frame(height: 168)
            }
            .refreshable { await viewModel.refresh() }
        }
    }
}
