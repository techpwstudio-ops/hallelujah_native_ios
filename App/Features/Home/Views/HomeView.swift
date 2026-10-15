import SwiftUI
import Observation

/// One `HomeFeedViewModel` per content type, created on first use and kept for
/// the life of the tab so flipping All / Music / Podcast back and forth shows
/// each feed's already-loaded rails instantly (the V2 repository keeps one feed
/// provider per type — `homeV2FeedProvider(songType.name)` — for the same
/// reason).
@MainActor
@Observable
final class HomeFeedStore {
    @ObservationIgnored private var models: [HomeContentType: HomeFeedViewModel] = [:]

    func model(for type: HomeContentType) -> HomeFeedViewModel {
        if let existing = models[type] { return existing }
        let model = HomeFeedViewModel(contentType: type)
        models[type] = model
        return model
    }

    func seed(_ model: HomeFeedViewModel) {
        models[model.contentType] = model
    }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// `ParallaxHeader` — the profile row drifts down at 0.3x the scroll offset so
/// it trails the content. Owns its own offset state so scrolling re-renders
/// only this block, not the whole feed.
private struct HomeParallaxHeaderBlock: View {
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HomeScrollOffsetKey.self,
                            value: -proxy.frame(in: .named(HomeView.scrollSpace)).minY
                        )
                    }
                )
            HomeHeaderView()
                .offset(y: max(0, scrollOffset) * 0.3)
        }
        .onPreferenceChange(HomeScrollOffsetKey.self) { scrollOffset = $0 }
    }
}

/// The Home tab's root content — ports `Home` (`lib/views/home/home_screen.dart`):
/// the profile row (parallax), the pinned All / Music / Podcast bar, then the
/// V2 feed — every rail drawn from the layout as a shimmer skeleton and filled
/// as it nears the viewport — with the vertical "Most Played Episodes" list
/// last, and a bottom spacer that clears the floating dock. Pull-to-refresh
/// re-reads the layout; a cold-start failure shows the centred message + Retry.
///
/// `LazyVStack`, not `VStack`: a rail only mounts (and so only calls
/// `HomeFeedViewModel.ensureLoaded(uiId:)` via its own `.task(id:)`) once it
/// nears the viewport, which is what makes the "on-demand fallback for a rail
/// the prefetch sweep hasn't reached yet" (`HOME_V2_API.md` §7) mean
/// something.
struct HomeView: View {
    static let scrollSpace = "homeScroll"

    @State private var store = HomeFeedStore()
    @State private var selected: HomeContentType = .all

    init() {}

    init(viewModel: HomeFeedViewModel) {
        let store = HomeFeedStore()
        store.seed(viewModel)
        _store = State(initialValue: store)
        _selected = State(initialValue: viewModel.contentType)
    }

    var body: some View {
        let model = store.model(for: selected)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                NoNetworkBanner()
                HomeParallaxHeaderBlock()
                Section {
                    feed(model)
                } header: {
                    HomeSongTypeBar(selection: $selected)
                }
            }
        }
        .coordinateSpace(name: Self.scrollSpace)
        // Opaque cover for the status-bar area, so the feed doesn't scroll
        // visibly behind the clock / Dynamic Island above the pinned bar.
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 0)
                .background(HomeColors.background.ignoresSafeArea(edges: .top))
        }
        .background(HomeColors.background.ignoresSafeArea())
        .refreshable {
            // A new feed session: rail ads are forgotten (`RailAdStore.reset`).
            RailAdStore.shared.reset()
            await model.refresh()
        }
        .task(id: selected) {
            await model.loadIfNeeded()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Feed

    @ViewBuilder
    private func feed(_ model: HomeFeedViewModel) -> some View {
        let placeholders = model.orderedPlaceholders
        if placeholders.isEmpty {
            emptyFeed(model)
        } else {
            Color.clear.frame(height: Dimens.screenPaddingAll * 2)
            // `listSongs` is a vertical list, not a rail, and always the last
            // thing in the feed (`HomeV2ListSongsSliver`).
            ForEach(placeholders.filter { $0.viewType != "listSongs" }) { placeholder in
                HomeSectionRailView(placeholder: placeholder, viewModel: model)
                // An ad banner renders right after its anchor rail
                // (`_kHomeAdBannerSpots`); a slot with no ad collapses to nothing.
                if let spot = HomeAdBannerSpot.spot(forAnchorKey: placeholder.key) {
                    HomeAdBannerSlot(spot: spot)
                }
            }
            ForEach(placeholders.filter { $0.viewType == "listSongs" }) { placeholder in
                HomeSectionRailView(placeholder: placeholder, viewModel: model)
            }
            Color.clear.frame(height: Dimens.screenPaddingAll * 2)
        }
        Color.clear.frame(height: HomeMetrics.feedBottomSpacing)
    }

    /// Nothing laid out yet: the single cold-start spinner, or — once the
    /// layout fetch has failed with nothing cached — the message and Retry.
    @ViewBuilder
    private func emptyFeed(_ model: HomeFeedViewModel) -> some View {
        if let error = model.layoutError {
            VStack(spacing: Dimens.spacing12) {
                Text(error)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(Color.white)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Text("Retry")
                        .typography(Typography.labelLarge)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, Dimens.spacing24)
                        .frame(minHeight: 40)
                        .background(HomeColors.darkFill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.white)
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }
}
