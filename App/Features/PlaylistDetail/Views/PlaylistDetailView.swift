import SwiftUI

/// "Album songs" / "company playlist songs", unified the way `Playlist`
/// unifies `CreatorPlaylist`/`CompanyPlaylist`, with each owner keeping its own
/// Flutter layout:
///
/// - **Creator playlist** (album / season) — `PlaylistSongPage`
///   (`album_songs_page.dart`): a square hero image under a transparent pinned
///   bar (parallax, top + bottom scrim, title fading in 200ms once the hero is
///   nearly gone), a 24pt title with "<n> Songs|Podcasts" beneath, and on the
///   right Shuffle, Add to Library, More and a filled Play/Pause.
/// - **Company playlist** — `CompanyPlaylistSongsPage`
///   (`company_playlist_songs_page.dart`): a solid black bar with the centred
///   title always visible, the cover as a plain square BELOW the bar (no scrim —
///   the baked-in logo corner must stay clear), a controls row (Shuffle, Add to
///   Library, Share, More … Play), an expandable "Description", then the songs.
///
/// Both then list the playlist's songs, paginated, with the shared song row.
struct PlaylistDetailView: View {
    @State private var viewModel: PlaylistDetailViewModel
    @State private var menuTarget: ContentMenuTarget?
    @State private var isShareSheetPresented = false
    @State private var scroll = HomeScrollState()

    @Environment(AppNavigationCoordinator.self) private var coordinator

    init(playlist: Playlist) {
        _viewModel = State(initialValue: PlaylistDetailViewModel(playlist: playlist))
    }

    private var playlist: Playlist { viewModel.playlist }
    private var isCompany: Bool { playlist.owner == .company }
    private var isMusic: Bool { playlist.type == "music" }

    private var source: QueueAttribution {
        if isCompany {
            return QueueAttribution(playerType: .companyPlaylist, id: playlist.id, title: playlist.title)
        }
        return QueueAttribution(playerType: isMusic ? .album : .season, id: playlist.id, title: "")
    }

    private var songs: [Song] {
        if case .loaded(let page) = viewModel.state { return page.items }
        return []
    }

    private static let paginationRunway = 4
    /// `Theme.textTheme.headlineSmall` (Material default: 24, w400, 1.33).
    private static let headlineSmall = TypographyToken(size: 24, weight: .regular, lineHeightMultiple: 1.33)

    var body: some View {
        Group {
            if isCompany {
                companyPage
            } else {
                albumPage
            }
        }
        .background(HomeColors.background.ignoresSafeArea())
        .contentMenu(target: $menuTarget)
        .appSheet(isPresented: $isShareSheetPresented, detents: [.large]) {
            ShareSheetView(
                target: .companyPlaylist(id: playlist.id),
                title: playlist.title,
                subtitle: nil,
                artworkURL: ArtworkURLResolver().resolve(path: playlist.image, variant: .lg, allowedVariants: playlist.imageVariants)
            )
        }
        .task { await viewModel.loadIfNeeded() }
    }

    // MARK: - Creator playlist (album / season)

    private var albumPage: some View {
        GeometryReader { geometry in
            // The square hero is the full width on a phone. Native-only
            // tablet/Mac adaptation: on a wider window it stops at a media
            // column, centred, with the title row and songs in that column.
            let heroSide = AdaptiveLayout.proportionalWidth(geometry.size.width)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HomeHeroHeader(
                        url: HomeArt.url(playlist.image, playlist.imageVariants, .lg),
                        width: heroSide,
                        state: scroll
                    )
                    .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
                    albumTitleRow
                        .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
                    songList(emptyText: "0 \((playlist.type ?? "").homeCapitalized)", verticalPadding: Dimens.screenPaddingAll)
                        .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
                    Color.clear.frame(height: HomeMetrics.pageBottomSpacing)
                }
            }
            .coordinateSpace(name: HomeHeroHeader.space)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                HomeCollapsedBarBackdrop(state: scroll, threshold: heroSide - 150)
            }
            .homeHeroChrome {
                HomeFadingTitle(title: playlist.title, state: scroll, opacity: { offset in
                    offset > heroSide - 150 ? 1 : 0
                }, animated: true, weight: .semibold)
            }
        }
    }

    private var albumTitleRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.title)
                    .typography(Self.headlineSmall)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.leading)
                Text(isMusic ? HomeFormat.songCountText(playlist.songsCount) : HomeFormat.podcastCountText(playlist.songsCount))
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(HomeColors.white70)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HomeShuffleButton()
            AddToLibraryButton(type: playlist.libraryItemType, itemID: playlist.id, title: playlist.title)
                .frame(width: 48, height: 48)
            moreButton
            Color.clear.frame(width: Dimens.spacing8)
            playButton
        }
        .padding(.horizontal, Dimens.screenPaddingAll * 2)
    }

    // MARK: - Company playlist

    private var companyPage: some View {
        GeometryReader { geometry in
            // Same native-only tablet/Mac adaptation as `albumPage`: the
            // square cover stops at a media column, centred, above the rest.
            let coverSide = AdaptiveLayout.proportionalWidth(geometry.size.width)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ArtworkView(
                        url: HomeArt.url(playlist.image, playlist.imageVariants, .lg),
                        width: coverSide,
                        height: coverSide,
                        cornerRadius: 0
                    )
                    .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
                    companyInfo
                        .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
                    songList(emptyText: String(localized: "No songs yet"), verticalPadding: 0)
                        .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
                    Color.clear.frame(height: HomeMetrics.pageBottomSpacing)
                }
            }
        }
        .appNavigationBarBackground()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(playlist.title)
                    .typography(Typography.titleMedium)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
        }
    }

    private var companyInfo: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Dimens.spacing16)
            HStack(spacing: 0) {
                HomeShuffleButton()
                Color.clear.frame(width: Dimens.spacing8)
                AddToLibraryButton(type: playlist.libraryItemType, itemID: playlist.id, title: playlist.title)
                    .frame(width: 48, height: 48)
                Button { isShareSheetPresented = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
                moreButton
                Spacer(minLength: 0)
                playButton
            }
            if let description = playlist.description?.homeTrimmed, !description.isEmpty {
                Color.clear.frame(height: Dimens.spacing16)
                Text("Description")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(Color.white)
                HomeExpandableText(
                    text: description,
                    token: Typography.bodySmall,
                    color: HomeColors.white50
                )
            }
            Color.clear.frame(height: Dimens.spacing16)
        }
        .padding(.horizontal, Dimens.screenPaddingAll + 12)
    }

    // MARK: - Shared controls

    /// `IconButton(Icons.more_vert)`.
    private var moreButton: some View {
        Button { menuTarget = .playlist(playlist) } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 22))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }

    private var playButton: some View {
        Button {
            HomePlayback.shared.playFirst(of: songs, source: source, coordinator: coordinator)
        } label: {
            HomePlayPauseFilled(source: source)
                .padding(Dimens.spacing8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Song list

    @ViewBuilder
    private func songList(emptyText: String, verticalPadding: CGFloat) -> some View {
        switch viewModel.state {
        case .loading:
            HomeSpinner()
                .frame(maxWidth: .infinity, minHeight: 300)
        case .empty, .failed:
            HomeEmptyText(text: emptyText)
                .frame(minHeight: 300)
        case .loaded(let page):
            LazyVStack(spacing: 0) {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, song in
                    HomeSongListRow(song: song, songs: page.items, source: source)
                        .onAppear {
                            if index >= page.items.count - Self.paginationRunway { viewModel.loadMore() }
                        }
                }
                if viewModel.isLoadingMore {
                    HomePageLoadingRow()
                }
            }
            .padding(.horizontal, Dimens.screenPaddingAll)
            .padding(.vertical, verticalPadding)
        }
    }
}
