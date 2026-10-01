import SwiftUI

/// The Home tab's root content (`AppShellView`'s `.home` case) — ports
/// `HomeScreen`'s (`lib/views/home/home_screen.dart`) sliver-of-rails
/// structure at a STRUCTURAL level only: one rank-ordered vertical stack of
/// rails, each a horizontal `ScrollView`. Dart's per-viewType visual
/// treatments — `trending`'s overlapping-card carousel, the two-column
/// playlist/recommendation grids, `singleCompanyPlaylist`'s hero card — are
/// a deliberate scope cut (T28's Status log has the full note); no
/// pixel-parity requirement applies here the way it does for splash/auth
/// (D10).
///
/// `LazyVStack`, not `VStack`: a rail only mounts (and so only calls
/// `HomeFeedViewModel.ensureLoaded(uiId:)` via its own `.task(id:)`) once it
/// nears the viewport, which is what makes "on-demand fallback for a rail
/// the prefetch sweep hasn't reached yet" (`HOME_V2_API.md` §7) actually
/// mean something — an eager `VStack` would fire every rail's fallback at
/// once on first render, defeating the sweep's own sequential pacing.
struct HomeView: View {
    @State private var viewModel: HomeFeedViewModel

    init(viewModel: HomeFeedViewModel = HomeFeedViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(viewModel.orderedPlaceholders) { placeholder in
                    HomeSectionRailView(placeholder: placeholder, viewModel: viewModel)
                }
            }
            .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .overlay {
            if viewModel.orderedPlaceholders.isEmpty {
                if viewModel.isRefreshing {
                    LoadingStateView()
                } else {
                    EmptyStateView(title: "Nothing here yet")
                }
            }
        }
    }
}
