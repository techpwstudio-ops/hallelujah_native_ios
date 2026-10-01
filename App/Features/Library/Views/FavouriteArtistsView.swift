import SwiftUI

/// Ports `FavouriteArtistPage` (`lib/views/library/grid_artists_favorite.dart`):
/// a paginated grid of already-followed creators — see
/// `FavouriteArtistsViewModel`'s own doc comment for why there's no
/// checkbox/multi-select and no "+" add-creators action here.
///
/// Grid cells DO tap through, to `.creatorSongs`: a direct read of
/// `CreatorGridItem`'s own `onTap` (`lib/widgets/creator/
/// creator_grid_item.dart:77-94`) shows `showCheckBox: false` (how this
/// screen's own `grid_artists_favorite.dart:137-141` always builds its
/// cells) only disables the multi-select checkbox behavior, not navigation —
/// the non-checkbox branch still calls
/// `NavigationService.to(CreatorSongsPage.routeName, arguments: {'creator_id': ...})`.
/// A prior pass here wrongly assumed "no tap-through" by checking for
/// `CreatorProfileView` call sites, the wrong destination; `.creatorSongs`
/// already has an established native push pattern
/// (`ContentSearchView.openCreator`), reused here. `.creatorSongs`'s own
/// destination screen is still a placeholder in `AppShellView` — that gap is
/// pre-existing and out of T44's scope, same as it is for
/// `ContentSearchView`'s own creator taps.
struct FavouriteArtistsView: View {
    @State private var viewModel: FavouriteArtistsViewModel
    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private static let gridColumns = [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible())]

    init(songType: String) {
        _viewModel = State(initialValue: FavouriteArtistsViewModel(songType: songType))
    }

    var body: some View {
        ScrollView {
            grid
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
        }
        .background(theme.color(.backgroundPrimary))
        .task { await viewModel.onAppear() }
    }

    private var grid: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: Spacing.md) {
            ForEach(viewModel.creators) { creator in
                Button {
                    coordinator.push(.creatorSongs(creatorID: creator.id, userPlaylistID: nil))
                } label: {
                    HomeCreatorCardView(creator: creator)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .task { await viewModel.loadMoreCreatorsIfNeeded(currentItem: creator) }
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isLoadingCreators {
                LoadingStateView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if viewModel.hasLoadedOnce, viewModel.creators.isEmpty {
                EmptyStateView(title: "No favourite artists yet")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }
}
