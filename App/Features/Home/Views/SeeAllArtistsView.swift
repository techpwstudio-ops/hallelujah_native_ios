import SwiftUI

/// Ports `SeeAllArtistsPage` (`lib/views/home/see_all_artists.dart`): a bold
/// 20pt (w900) title in the bar, the tappable "Search" bar (opens the creator
/// search), then a grid of creators — max 100pt columns, 12 apart,
/// 0.75 child aspect ratio, 16 horizontal padding — that pages in as you scroll.
struct SeeAllArtistsView: View {
    @State private var viewModel: SectionDetailViewModel

    @Environment(AppNavigationCoordinator.self) private var coordinator

    let title: String

    private static let paginationRunway = 6

    init(type: String?, title: String, uiId: String?) {
        self.title = title
        let contentType = type.flatMap { HomeContentType(rawValue: $0) } ?? .all
        _viewModel = State(initialValue: SectionDetailViewModel(
            uiId: uiId ?? "", title: title, contentType: contentType
        ))
    }

    private var creators: [Creator] {
        if case .loaded(let content) = viewModel.state, case .creators(let page) = content {
            return page.items
        }
        return []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                searchBar
                grid
                Color.clear.frame(height: HomeMetrics.pageBottomSpacing)
            }
        }
        .background(HomeColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .typography(Typography.titleLarge)
                    .fontWeight(.black)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    /// `SearchWidgetUi` — fill 0xFF1D1D1D, radius 8, a 20pt search glyph and a
    /// grey "Search" hint; 8 outer + 8 inner padding (70pt tall in total).
    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(Color.white)
                .padding(Dimens.spacing8)
            Text("Search")
                .typography(Typography.bodyMedium)
                .foregroundStyle(Color.gray.opacity(0.7))
                .padding(Dimens.spacing4)
            Spacer(minLength: 0)
        }
        .padding(Dimens.spacing8)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: 8, style: .circular))
        .padding(Dimens.spacing8)
        .padding(Dimens.screenPaddingAll)
        .contentShape(Rectangle())
        .onTapGesture {
            coordinator.push(.contentSearch(userPlaylistID: nil, tags: [], checkedContent: [], isSelect: false))
        }
    }

    @ViewBuilder
    private var grid: some View {
        switch viewModel.state {
        case .loading:
            HomeSpinner()
                .frame(maxWidth: .infinity, minHeight: 300)
        case .empty, .failed:
            EmptyView()
        case .loaded:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12, alignment: .top)],
                alignment: .center,
                spacing: 12
            ) {
                ForEach(Array(creators.enumerated()), id: \.element.id) { index, creator in
                    HomeCreatorCardView(creator: creator, trailingGap: 0)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            if index >= creators.count - Self.paginationRunway { viewModel.loadMore() }
                        }
                }
                if viewModel.isLoadingMore {
                    HomeSpinner()
                }
            }
            .padding(.horizontal, Dimens.screenPaddingAll * 2)
            .padding(.vertical, Dimens.screenPaddingAll)
        }
    }
}
