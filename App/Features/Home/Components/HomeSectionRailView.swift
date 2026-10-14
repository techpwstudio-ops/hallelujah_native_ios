import SwiftUI

/// `_SectionError` — the small, quiet placeholder a failed rail leaves in its
/// place: the section header (when it has one) over a left-aligned
/// "Tap to retry" text button with a 16pt refresh glyph, white54.
struct HomeSectionErrorView: View {
    var title: String?
    let onRetry: () -> Void

    var body: some View {
        HomeSectionContainer(layout: .fullWidth, title: title) {
            HStack {
                Button(action: onRetry) {
                    HStack(spacing: Dimens.spacing8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                        Text("Tap to retry")
                            .typography(Typography.labelLarge)
                    }
                    .foregroundStyle(HomeColors.white50)
                    .padding(.horizontal, Dimens.spacing12)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
    }
}

/// One feed section: drives the `HomeRailLoadState` machine (a mounted row
/// asks for itself via `.task(id:)`, so a `LazyVStack` mounting it IS the
/// "approaching the viewport" signal — `_SectionSlotState._requestIfNeeded`)
/// and dispatches the loaded content by `viewType`, exactly as
/// `buildHomeListItem` / `HomeV2FeedSliver._SectionSlot` do.
struct HomeSectionRailView: View {
    let placeholder: HomeSectionPlaceholder
    let viewModel: HomeFeedViewModel

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        if placeholder.viewType == "verseOfDay" {
            // `_VerseOfDaySection`: a full-width block with no generic header
            // and a hidden verse takes up no space at all.
            VerseOfDayCardView()
                .padding(.horizontal, Dimens.sectionPaddingH)
        } else {
            railBody
                .task(id: placeholder.id) {
                    viewModel.ensureLoaded(uiId: placeholder.id)
                }
        }
    }

    @ViewBuilder
    private var railBody: some View {
        switch viewModel.state(for: placeholder.id) {
        case .placeholder, .loading, .degraded:
            HomeSectionSkeletonView(
                viewType: placeholder.viewType,
                title: placeholder.title,
                type: placeholder.type
            )
        case .empty:
            EmptyView()
        case .failed:
            HomeSectionErrorView(
                title: placeholder.viewType == "listSongs" ? nil : placeholder.title,
                onRetry: { viewModel.reloadSection(uiId: placeholder.id) }
            )
        case .loaded(let section):
            loaded(section)
        }
    }

    // MARK: Loaded content

    @ViewBuilder
    private func loaded(_ section: ContentSection) -> some View {
        switch section.content {
        case .songs(let page):
            songsSection(section, songs: page.items.filter { $0.isHomeShowable })
        case .creators(let page):
            creatorsSection(section, creators: page.items)
        case .playlists(let page):
            playlistsSection(section, playlists: page.items)
        case .recentItems(let page):
            recentSection(section, items: page.items)
        case .unsupported:
            EmptyView()
        }
    }

    @ViewBuilder
    private func songsSection(_ section: ContentSection, songs: [Song]) -> some View {
        let isEpisode = section.type == "episode" || section.viewType == "episodes"
        if songs.isEmpty {
            EmptyView()
        } else {
            switch section.viewType {
            case "trending":
                HomeSectionContainer(layout: .bleed, title: section.title) {
                    HomeTrendingCarouselView(songs: songs, uiId: section.id, isEpisode: section.type == "episode")
                }
            case "listSongs":
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        HomeListSongCardView(song: song, songs: songs, uiId: section.id)
                    }
                }
                .padding(.horizontal, HomeMetrics.listInset)
            case "recommended" where !isEpisode:
                HomeSectionContainer(
                    layout: .fullWidth,
                    title: section.title,
                    onSeeAll: { openSeeAllSongs(section, songs: songs) }
                ) {
                    HomeRecommendationGridView(songs: songs, uiId: section.id)
                }
            default:
                HomeSectionContainer(
                    layout: .horizontalRow,
                    title: section.title,
                    onSeeAll: { openSeeAllSongs(section, songs: songs) }
                ) {
                    HomeRailScroll {
                        ForEach(songs) { song in
                            HomeSongCardView(song: song, songs: songs, uiId: section.id, isEpisode: isEpisode)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func creatorsSection(_ section: ContentSection, creators: [Creator]) -> some View {
        if creators.isEmpty {
            EmptyView()
        } else if section.viewType == "podcasts" {
            HomeSectionContainer(
                layout: .horizontalRow,
                title: section.title,
                onSeeAll: { openSeeAllArtists(section) }
            ) {
                HomeRailScroll {
                    ForEach(creators) { creator in
                        HomePodcastCardView(creator: creator)
                    }
                }
            }
        } else {
            HomeSectionContainer(
                layout: .horizontalRow,
                title: section.title,
                onSeeAll: { openSeeAllArtists(section) }
            ) {
                HomeRailScroll(height: Dimens.creatorRowHeight) {
                    ForEach(creators) { creator in
                        HomeCreatorCardView(creator: creator)
                    }
                    Color.clear.frame(width: Dimens.horizontalGapMedium)
                }
            }
        }
    }

    @ViewBuilder
    private func playlistsSection(_ section: ContentSection, playlists: [Playlist]) -> some View {
        if playlists.isEmpty {
            EmptyView()
        } else {
            switch section.viewType {
            case "singleCompanyPlaylist":
                if let top = playlists.first {
                    HomeSectionContainer(layout: .fullWidth, title: section.title) {
                        HomeTopWeeklyPlaylistCardView(playlist: top)
                    }
                }
            case "companyPlaylists":
                HomeSectionContainer(layout: .fullWidth, title: section.title) {
                    HomeCompanyPlaylistGridView(playlists: playlists)
                }
            case "similarPlaylist":
                HomeSectionContainer(layout: .bleed) {
                    HomeSimilarPlaylistView(playlists: playlists)
                }
            case "playlists":
                HomeSectionContainer(layout: .horizontalRow, title: section.title) {
                    HomeRailScroll {
                        ForEach(playlists) { playlist in
                            HomePlaylistCardView(playlist: playlist, style: .album)
                        }
                    }
                }
            default:
                HomeSectionContainer(layout: .horizontalRow, title: section.title) {
                    HomeRailScroll {
                        ForEach(playlists) { playlist in
                            HomePlaylistCardView(playlist: playlist, style: .company)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentSection(_ section: ContentSection, items: [RecentContentItem]) -> some View {
        // The server already drops episodes on the All tab (an episode is a
        // wide 16:9 card, everything else a square, and mixing the two widths
        // in one strip reads as broken layout); applied again here for stale
        // cached payloads.
        let visible = viewModel.contentType == .all ? items.filter { !$0.isEpisode } : items
        if visible.isEmpty {
            EmptyView()
        } else {
            HomeSectionContainer(layout: .horizontalRow, title: section.title) {
                HomeRailScroll {
                    ForEach(visible) { item in
                        HomeRecentItemCardView(item: item, uiId: section.id)
                    }
                }
            }
        }
    }

    // MARK: See all

    private func openSeeAllSongs(_ section: ContentSection, songs: [Song]) {
        let first = songs.first
        if section.id == "recent-all" {
            coordinator.push(.recentSongs(
                image: first?.image,
                viewType: section.viewType,
                label: section.title,
                songIDs: songs.map { Optional($0.id) },
                imageURL: nil,
                imageVariants: first?.imageVariants
            ))
        } else {
            coordinator.push(.seeAllSongs(
                type: section.type,
                viewType: section.viewType,
                image: first?.image,
                imageVariants: first?.imageVariants,
                imageURL: nil,
                uniqueIDWithType: section.id,
                label: section.title,
                songIDs: songs.map { Optional($0.id) },
                homeListUnitModelDataID: section.id
            ))
        }
    }

    private func openSeeAllArtists(_ section: ContentSection) {
        coordinator.push(.seeAllArtists(
            type: section.type,
            title: section.title,
            homeListUnitModelDataID: section.id,
            viewType: section.viewType
        ))
    }
}
