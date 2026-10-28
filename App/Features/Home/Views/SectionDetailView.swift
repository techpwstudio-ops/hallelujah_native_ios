import SwiftUI

/// T29's generic "see all" screen — one rank-agnostic scroll of a single
/// rail's full paginated content, dispatched by `SectionContent`'s case for
/// card shape only (`SectionDetailViewModel`'s doc comment has the full
/// "why one screen" rationale). No navigation entry point is wired to this
/// yet — Home's rails aren't tap-navigable at all yet (same scope cut T28's
/// Status log already noted), consistent with T30's own precedent that a
/// screen's own "reachable from" wiring isn't its Done criterion.
struct SectionDetailView: View {
    @State private var viewModel: SectionDetailViewModel
    @Environment(\.layoutWidth) private var layoutWidth

    init(uiId: String, title: String, contentType: HomeContentType) {
        _viewModel = State(initialValue: SectionDetailViewModel(uiId: uiId, title: title, contentType: contentType))
    }

    /// Two columns on a phone. Native-only tablet/Mac adaptation (no Flutter
    /// counterpart): a wider window adds columns so cells stay phone-sized.
    private var gridColumns: [GridItem] {
        let count = HomeMetrics.gridColumns(in: layoutWidth)
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: count - 1) + [GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            content
                .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .empty:
            EmptyStateView(title: String(localized: "Nothing here yet"))
        case .failed:
            ErrorStateView(
                title: String(localized: "Couldn't load this"),
                onRetry: { Task { await viewModel.refresh() } }
            )
        case .loaded(let section):
            loadedContent(section)
        }
    }

    @ViewBuilder
    private func loadedContent(_ section: SectionContent) -> some View {
        switch section {
        case .songs(let page):
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, song in
                    CreatorSongRow(song: song)
                        .padding(.horizontal, Spacing.md)
                        .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                }
            }
            // Native-only tablet/Mac adaptation: rows keep to a readable column.
            .readableContentWidth()
        case .creators(let page):
            LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, creator in
                    HomeCreatorCardView(creator: creator)
                        .frame(maxWidth: .infinity)
                        .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                }
            }
            .padding(.horizontal, Spacing.md)
        case .recentItems(let page):
            LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, item in
                    HomeRecentItemCardView(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                }
            }
            .padding(.horizontal, Spacing.md)
        case .playlists, .unsupported:
            // Not one of T29's five bullets — no "see all playlists" screen
            // exists in Dart either. Kept as a safe fallback rather than
            // `fatalError` in case a future caller points this view at a
            // playlists-viewType uiId.
            EmptyStateView(title: String(localized: "Nothing here yet"))
        }
    }

    private func loadMoreIfNeeded(index: Int, count: Int) {
        guard index >= count - 2 else { return }
        viewModel.loadMore()
    }
}
