import SwiftUI

/// One rail: title header plus whichever of `HomeRailLoadState`'s five
/// states `viewModel` currently has for `placeholder.id`. Drives that state
/// machine itself — `.task(id:)` calls `ensureLoaded(uiId:)` when this row
/// mounts, which is exactly when a `LazyVStack` mounts a row scrolling
/// toward the viewport, matching §7's "on-demand fallback for a rail that
/// reaches the viewport before the prefetch sweep gets to it." Both calls
/// are idempotent no-ops unless the rail is genuinely idle, so mounting
/// twice (a `LazyVStack` re-mounting a row that scrolled off-screen and
/// back) safely re-arms a rail instead of ever double-requesting it.
struct HomeSectionRailView: View {
    let placeholder: HomeSectionPlaceholder
    let viewModel: HomeFeedViewModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        // T56 — Flutter's `_VerseOfDaySection` (`VerseOfDayUi`) is a
        // fully custom full-width card with no generic rail title header,
        // and it's driven purely by local state/Realm, never by the
        // generic section-fetch API — so this special case returns before
        // the title `VStack` is even built, and deliberately has no
        // `.task(id:)`/`ensureLoaded(uiId:)` call of its own.
        if placeholder.viewType == "verseOfDay" {
            VerseOfDayCardView()
                .padding(.horizontal, Spacing.md)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(placeholder.title)
                    .typography(Typography.titleMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .padding(.horizontal, Spacing.md)

                content
            }
            .task(id: placeholder.id) {
                viewModel.ensureLoaded(uiId: placeholder.id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state(for: placeholder.id) {
        case .placeholder, .loading, .degraded:
            skeleton
        case .loaded(let section):
            HomeSectionContentRailView(section: section, viewModel: viewModel)
        case .empty:
            // Never reached in practice — `HomeFeedViewModel.orderedPlaceholders`
            // already drops `.empty` rails (widget AND title, per §7), so this
            // row isn't even mounted for one. Kept as a safe fallback rather
            // than `fatalError` in case a future caller iterates
            // `placeholders` directly instead.
            EmptyView()
        case .failed:
            ErrorStateView(
                title: "Couldn't load this section",
                onRetry: { viewModel.ensureLoaded(uiId: placeholder.id) }
            )
        }
    }

    @ViewBuilder
    private var skeleton: some View {
        if placeholder.viewType == "creators" {
            HomeRailSkeleton(
                itemSize: HomeCreatorCardView.avatarSize,
                cornerRadius: HomeCreatorCardView.avatarSize / 2,
                lineCount: 1,
                centered: true
            )
        } else {
            HomeRailSkeleton(itemSize: HomeSongCardView.coverSize, cornerRadius: Radius.md, lineCount: 2)
        }
    }
}

/// The real, hydrated rail — one horizontal `ScrollView` dispatched by
/// `section.content`'s case. Triggers `loadMore` one card of runway before
/// the true end, per §7's `meta.hasMore`-driven pagination.
private struct HomeSectionContentRailView: View {
    let section: ContentSection
    let viewModel: HomeFeedViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md) {
                switch section.content {
                case .songs(let page):
                    ForEach(Array(page.items.enumerated()), id: \.element.id) { index, song in
                        HomeSongCardView(song: song)
                            .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                    }
                case .creators(let page):
                    ForEach(Array(page.items.enumerated()), id: \.element.id) { index, creator in
                        HomeCreatorCardView(creator: creator)
                            .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                    }
                case .playlists(let page):
                    ForEach(Array(page.items.enumerated()), id: \.element.id) { index, playlist in
                        HomePlaylistCardView(playlist: playlist)
                            .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                    }
                case .recentItems(let page):
                    ForEach(Array(page.items.enumerated()), id: \.element.id) { index, item in
                        HomeRecentItemCardView(item: item)
                            .onAppear { loadMoreIfNeeded(index: index, count: page.items.count) }
                    }
                case .unsupported:
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func loadMoreIfNeeded(index: Int, count: Int) {
        guard index >= count - 2 else { return }
        viewModel.loadMore(uiId: section.id)
    }
}

/// A rail-shaped shimmer: `Self.itemCount` identical placeholder cards
/// under one `.shimmer()` sweep, per `ShimmerModifier`'s own "one shimmer
/// per section" cost rule.
private struct HomeRailSkeleton: View {
    let itemSize: CGFloat
    let cornerRadius: CGFloat
    let lineCount: Int
    var centered = false

    private static let itemCount = 5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(0..<Self.itemCount, id: \.self) { _ in
                    VStack(alignment: centered ? .center : .leading, spacing: Spacing.xs) {
                        SkeletonBox(width: itemSize, height: itemSize, radius: cornerRadius)
                        ForEach(0..<lineCount, id: \.self) { line in
                            SkeletonBox(width: itemSize * (line == 0 ? 0.9 : 0.55), height: 12, radius: Radius.sm)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .shimmer()
        .allowsHitTesting(false)
    }
}
