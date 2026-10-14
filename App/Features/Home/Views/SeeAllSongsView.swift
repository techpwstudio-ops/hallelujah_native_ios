import SwiftUI

/// Ports `SeeAllSongPage` (`lib/views/home/see_all_songs_page.dart`): a square
/// hero image (parallax, top + bottom scrim) under a pinned bar whose title
/// fades in over the first 8-72pt of scroll, a 24pt title row with Shuffle and
/// a filled Play/Pause, then the rail's full, paginated song list.
///
/// Reached from `AppRoute.seeAllSongs`; the shell constructs it with the
/// route's fields. One screen, driven by `SectionDetailViewModel`'s
/// `fetchSection(uiId:page:)` paging — the V2 equivalent of the V1
/// `HomeViewMoreSongsBloc` load this page used.
struct SeeAllSongsView: View {
    @State private var viewModel: SectionDetailViewModel
    @State private var scroll = HomeScrollState()

    @Environment(AppNavigationCoordinator.self) private var coordinator

    let label: String
    let image: String?
    let imageVariants: String?
    let uniqueID: String?

    /// `Theme.textTheme.headlineSmall` (Material default: 24, w400, 1.33).
    private static let headlineSmall = TypographyToken(size: 24, weight: .regular, lineHeightMultiple: 1.33)
    private static let paginationRunway = 4

    init(
        type: String?,
        image: String?,
        imageVariants: String?,
        uniqueID: String?,
        label: String
    ) {
        self.label = label
        self.image = image
        self.imageVariants = imageVariants
        self.uniqueID = uniqueID
        let contentType = type.flatMap { HomeContentType(rawValue: $0) } ?? .all
        _viewModel = State(initialValue: SectionDetailViewModel(
            uiId: uniqueID ?? "", title: label, contentType: contentType
        ))
    }

    private var source: QueueAttribution {
        HomePlayback.homeAttribution(uiId: uniqueID)
    }

    private var songs: [Song] {
        if case .loaded(let content) = viewModel.state, case .songs(let page) = content {
            return page.items
        }
        return []
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HomeHeroHeader(
                        url: HomeArt.url(image, imageVariants, .lg),
                        width: geometry.size.width,
                        state: scroll
                    )
                    titleRow
                    list
                    Color.clear.frame(height: HomeMetrics.pageBottomSpacing)
                }
            }
            .coordinateSpace(name: HomeHeroHeader.space)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                HomeCollapsedBarBackdrop(state: scroll, threshold: geometry.size.width - 100)
            }
        }
        .background(HomeColors.background.ignoresSafeArea())
        .homeHeroChrome {
            HomeFadingTitle(title: label, state: scroll) { offset in
                Double(min(max((offset - 8) / (72 - 8), 0), 1))
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    private var titleRow: some View {
        HStack(spacing: 0) {
            Text(label)
                .typography(Self.headlineSmall)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            HomeShuffleButton()
            Button {
                HomePlayback.shared.playFirst(of: songs, source: source, coordinator: coordinator)
            } label: {
                HomePlayPauseFilled(source: source)
                    .padding(Dimens.spacing8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Dimens.screenPaddingAll * 2)
        .padding(.vertical, Dimens.screenPaddingAll)
    }

    @ViewBuilder
    private var list: some View {
        switch viewModel.state {
        case .loading:
            HomeSpinner()
                .frame(maxWidth: .infinity, minHeight: 300)
        case .empty, .failed:
            HomeEmptyText(text: "Your feed is empty")
                .frame(minHeight: 300)
        case .loaded:
            if songs.isEmpty {
                HomeEmptyText(text: "Your feed is empty")
                    .frame(minHeight: 300)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        HomeSongListRow(song: song, songs: songs, source: source)
                            .onAppear {
                                if index >= songs.count - Self.paginationRunway { viewModel.loadMore() }
                            }
                    }
                    if viewModel.isLoadingMore {
                        HomePageLoadingRow()
                    }
                }
                .padding(.horizontal, Dimens.screenPaddingAll)
                .padding(.vertical, Dimens.screenPaddingAll)
            }
        }
    }
}
