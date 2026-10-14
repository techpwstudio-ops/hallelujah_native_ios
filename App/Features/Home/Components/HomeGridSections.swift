import SwiftUI

/// One grid row: two items, the right one absent on an odd tail.
private struct HomePairRow<T>: Identifiable {
    let id: Int
    let left: T
    let right: T?
}

/// Pairs `items` two to a row.
private func homePairs<T>(_ items: [T]) -> [HomePairRow<T>] {
    var rows: [HomePairRow<T>] = []
    var index = 0
    while index < items.count {
        rows.append(HomePairRow(id: index, left: items[index], right: index + 1 < items.count ? items[index + 1] : nil))
        index += 2
    }
    return rows
}

/// `HomeSongRecommendationUi` — a two-column grid of compact song cards
/// (`recommended` viewType, music): fill 0xFF1D1D1D, radius 8, 8 padding, a 40
/// cover (radius 4, `sm`), 12 gap and a two-line `bodyMedium` w600 title.
/// Rows and columns are 10 apart; both cards in a row share one height.
struct HomeRecommendationGridView: View {
    let songs: [Song]
    let uiId: String

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: HomeMetrics.recommendationGap) {
            ForEach(homePairs(songs)) { row in
                HStack(spacing: HomeMetrics.recommendationGap) {
                    card(row.left)
                    if let right = row.right {
                        card(right)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(_ song: Song) -> some View {
        HStack(spacing: HomeMetrics.recommendationCoverToTitleGap) {
            ArtworkView(
                url: HomeArt.url(song.displayImage, song.displayImageVariants, .sm),
                width: HomeMetrics.recommendationCover,
                height: HomeMetrics.recommendationCover,
                cornerRadius: Dimens.cornerRadiusSmall
            )
            Text((song.title ?? "").homeCapitalized.homeTrimmed)
                .typography(Typography.bodyMedium)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(HomeMetrics.recommendationPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .circular))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .circular))
        .onTapGesture {
            HomePlayback.shared.play(
                song: song,
                in: songs,
                source: HomePlayback.homeAttribution(uiId: uiId),
                coordinator: coordinator
            )
        }
    }
}

/// `HomeTopCompanyPlaylistUi` — the `companyPlaylists` section: a two-column
/// grid capped at six cards. Card: fill 0xFF1D1D1D, radius 12, 8 padding, a 56
/// cover (radius 4, `md`), 8 gap and a vertically-centred two-line titleSmall
/// w600 title (line height 1.25). Rows and columns are 8 apart.
struct HomeCompanyPlaylistGridView: View {
    let playlists: [Playlist]

    @Environment(AppNavigationCoordinator.self) private var coordinator

    private var capped: [Playlist] {
        Array(playlists.prefix(HomeMetrics.companyGridMaxItems))
    }

    var body: some View {
        VStack(spacing: HomeMetrics.companyGridGap) {
            ForEach(homePairs(capped)) { row in
                HStack(spacing: HomeMetrics.companyGridGap) {
                    card(row.left)
                    if let right = row.right {
                        card(right)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(_ playlist: Playlist) -> some View {
        HStack(spacing: Dimens.spacing8) {
            ArtworkView(
                url: HomeArt.url(playlist.image, playlist.imageVariants, .md),
                width: HomeMetrics.companyGridCover,
                height: HomeMetrics.companyGridCover,
                cornerRadius: Dimens.cornerRadiusSmall
            )
            Text(playlist.title.homeCapitalized.homeTrimmed)
                .typography(TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.25))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(HomeMetrics.companyGridGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .contentShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .onTapGesture { coordinator.push(playlist.detailRoute) }
    }
}

/// `HomeTopWeeklyPlaylistCard` — "Top This Week", the single-playlist hero
/// card (`singleCompanyPlaylist`): fill 0xFF1D1D1D, radius 12, 12 padding; a
/// 96 cover (radius 4) beside a titleLarge w700 two-line title, a three-line
/// bodyLarge white70 description (height 1.35) and a 48pt filled Play button on
/// the right that fetches page one of the playlist and plays it as
/// `PlayerType.companyPlaylist`. (The category-name line needs a field the v2
/// payload decoding does not carry yet; omitted.)
struct HomeTopWeeklyPlaylistCardView: View {
    let playlist: Playlist

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @State private var isLoading = false

    private var source: QueueAttribution {
        QueueAttribution(playerType: .companyPlaylist, id: playlist.id, title: playlist.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Dimens.spacing12) {
                ArtworkView(
                    url: HomeArt.url(playlist.image, playlist.imageVariants, .md),
                    width: HomeMetrics.weeklyCover,
                    height: HomeMetrics.weeklyCover,
                    cornerRadius: Dimens.cornerRadiusSmall
                )
                Text(playlist.title.homeCapitalized)
                    .typography(Typography.titleLarge)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let description = playlist.description?.homeTrimmed, !description.isEmpty {
                Color.clear.frame(height: Dimens.spacing12)
                Text(description)
                    .typography(TypographyToken(size: 16, weight: .regular, lineHeightMultiple: 1.35))
                    .foregroundStyle(HomeColors.white70)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Color.clear.frame(height: Dimens.spacing12)
            HStack {
                Spacer(minLength: 0)
                playButton
            }
        }
        .padding(HomeMetrics.weeklyPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .contentShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .onTapGesture { coordinator.push(playlist.detailRoute) }
    }

    @ViewBuilder
    private var playButton: some View {
        if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.white)
                .frame(width: 44, height: 44)
        } else {
            Button(action: play) {
                HomePlayPauseFilled(source: source)
            }
            .buttonStyle(.plain)
        }
    }

    private func play() {
        let playback = HomePlayback.shared
        if playback.isQueueActive(source) {
            playback.togglePlayPause()
            return
        }
        guard !isLoading else { return }
        isLoading = true
        let source = source
        let coordinator = coordinator
        let playlist = playlist
        Task { @MainActor in
            defer { isLoading = false }
            let repository: any PlaylistRepository = DependencyContainer.current.resolve()
            guard let page = try? await repository.fetchSongs(playlistId: playlist.id, owner: playlist.owner, page: 1),
                  let first = page.items.first else { return }
            playback.play(song: first, in: page.items, source: source, coordinator: coordinator)
        }
    }
}

/// `HomeSimilarPlaylistRow` — a "More Like <playlist>" section: the seed
/// playlist is the HEADER (48pt circular artwork, "More Like This" in
/// titleSmall white50 w600, its name in titleLarge w700), with the 120-cover
/// rail (height 164, radius 8, 16 apart) beneath. The header block is inset on
/// both sides, the rail on the left only.
struct HomeSimilarPlaylistView: View {
    let playlists: [Playlist]
    /// What this rail's square ads are filed under (`RailAdStore`); nil for none.
    var adRailId: String?

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        if let seed = playlists.first {
            VStack(alignment: .leading, spacing: 0) {
                seedHeader(seed)
                    .padding(.horizontal, Dimens.sectionPaddingH)
                Color.clear.frame(height: Dimens.horizontalSpacing)
                HomeRailScroll(height: HomeMetrics.similarRailHeight) {
                    HomeAdRailItems(layout: RailAdStore.shared.layoutFor(adRailId, playlists.count)) { index in
                        HomePlaylistCardView(playlist: playlists[index], style: .similar)
                    } ad: { slotId in
                        HomeRailAdSlot(
                            slotId: slotId,
                            size: HomeMetrics.similarCoverSize,
                            radius: Dimens.cornerRadius,
                            trailingGap: HomeMetrics.cardSpacing
                        )
                    }
                }
                .padding(.leading, Dimens.sectionPaddingH)
            }
        }
    }

    private func seedHeader(_ seed: Playlist) -> some View {
        HStack(spacing: Dimens.spacing12) {
            ArtworkView(
                url: HomeArt.url(seed.image, seed.imageVariants, .sm),
                width: HomeMetrics.similarSeedAvatar,
                height: HomeMetrics.similarSeedAvatar,
                cornerRadius: HomeMetrics.similarSeedAvatar / 2
            )
            VStack(alignment: .leading, spacing: 0) {
                Text("More Like This")
                    .typography(Typography.titleSmall)
                    .foregroundStyle(HomeColors.white50)
                Text(seed.title.homeCapitalized.homeTrimmed)
                    .typography(Typography.titleLarge)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { coordinator.push(seed.detailRoute) }
    }
}

/// `HomeListItemUi` — one full-width card of the vertical "Most Played
/// Episodes" list (`listSongs`): fill 0xFF1D1D1D, radius 12, 8 padding and a
/// soft shadow; a 16:9 cover with a faint bottom scrim, a creator avatar +
/// title + "creator • year • duration" row with a favourite heart and a play
/// ring, then a two-line description.
struct HomeListSongCardView: View {
    let song: Song
    let songs: [Song]
    let uiId: String

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @State private var isFavorited: Bool

    init(song: Song, songs: [Song], uiId: String) {
        self.song = song
        self.songs = songs
        self.uiId = uiId
        _isFavorited = State(initialValue: song.isFavorited)
    }

    private var meta: String {
        var parts: [String] = []
        if let name = song.creator?.name?.homeTrimmed, !name.isEmpty { parts.append(name) }
        if let year = song.productionYear { parts.append(String(year)) }
        parts.append(HomeFormat.durationText(song.duration))
        return parts.joined(separator: " \u{2022} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { proxy in
                        ZStack {
                            ArtworkView(
                                url: HomeArt.url(song.displayImage, song.displayImageVariants, .md),
                                width: proxy.size.width,
                                height: proxy.size.height,
                                cornerRadius: 0
                            )
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
            Color.clear.frame(height: Dimens.verticalSpacing)
            HStack(spacing: 0) {
                ArtworkView(
                    url: HomeArt.url(song.creator?.image, song.creator?.imageVariants, .sm),
                    width: HomeMetrics.listAvatar,
                    height: HomeMetrics.listAvatar,
                    cornerRadius: Dimens.cornerRadiusSmall
                )
                Color.clear.frame(width: Dimens.leadingSpacing)
                VStack(alignment: .leading, spacing: 4) {
                    Text((song.title ?? "").homeTrimmed)
                        .typography(Typography.titleSmall)
                        .tracking(0.2)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(meta)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(HomeColors.white70)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: Dimens.spacing8)
                Button(action: toggleFavourite) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: HomeMetrics.listFavouriteSize))
                        .foregroundStyle(Color.white)
                        .padding(Dimens.paddingSmall)
                }
                .buttonStyle(.plain)
                Color.clear.frame(width: Dimens.spacing4)
                HomePlayPauseIcon(songID: song.id, size: HomeMetrics.listPlaySize)
            }
            .padding(.horizontal, HomeMetrics.listCardPadding)
            Color.clear.frame(height: Dimens.verticalSpacing + 4)
            Text(song.description ?? "")
                .typography(TypographyToken(size: 12, weight: .regular, lineHeightMultiple: 1.4))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, HomeMetrics.listCardPadding)
        }
        .padding(HomeMetrics.listCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeColors.fill, in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
        .onTapGesture {
            HomePlayback.shared.play(
                song: song,
                in: songs,
                source: HomePlayback.homeAttribution(uiId: uiId),
                coordinator: coordinator
            )
        }
        .padding(.bottom, HomeMetrics.listInset)
    }

    private func toggleFavourite() {
        let target = !isFavorited
        isFavorited = target
        let songID = song.id
        Task { @MainActor in
            let repository: any FavouriteRepository = DependencyContainer.current.resolve()
            do {
                try await repository.toggleSongFavorite(songId: songID, isFavorited: target)
            } catch {
                isFavorited = !target
            }
        }
    }
}
