import SwiftUI

/// One card in the `recentMixed` "Continue Your Journey" rail —
/// `_RecentCard`. The rail is heterogeneous, so the SHAPE is per-card: music
/// gets the 98 square cover + two-line title, an episode gets the 256x144 wide
/// card with a scrim, a one-line title, an optional subtitle and a top-left
/// type badge. Tapping opens the container the card points at; a bare song
/// (or a container that cannot be resolved) resumes the track the server left
/// the card on.
struct HomeRecentItemCardView: View {
    let item: RecentContentItem
    /// The section uiId — becomes the player id of the resumed queue.
    var uiId: String = ""

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @State private var isResuming = false

    private static func badgeLabel(for itemType: String) -> String? {
        switch itemType {
        case "companyPlaylist": String(localized: "Playlist")
        case "album": String(localized: "Album")
        case "season": String(localized: "Season")
        case "userPlaylist": String(localized: "Your list")
        case "creator": String(localized: "Artist")
        default: nil
        }
    }

    static let coverSize: CGFloat = HomeMetrics.coverSize

    private var artworkURL: URL? { HomeArt.url(item.image, item.imageVariants, .md) }

    var body: some View {
        Group {
            if item.isEpisode, item.itemType == "creator" {
                artistWideCard
            } else if item.isEpisode {
                wideCard
            } else {
                HomeSquareCard(
                    url: artworkURL,
                    title: (item.title ?? "").homeTrimmed
                ) {
                    HomeRecentProgressBar(item: item)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var wideCard: some View {
        ZStack(alignment: .bottom) {
            ArtworkView(
                url: artworkURL,
                width: HomeMetrics.episodeCardWidth,
                height: HomeMetrics.episodeCardHeight,
                cornerRadius: 0
            )
            LinearGradient(gradient: HomeColors.episodeScrim, startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: Dimens.spacing12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text((item.title ?? "").homeTrimmed)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let subtitle = item.subtitle?.homeTrimmed, !subtitle.isEmpty {
                        Text(subtitle)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if item.isSong, let songID = item.songId {
                    HomePlayPauseIcon(songID: songID, size: 28)
                }
            }
            .padding(Dimens.spacing16)
        }
        .overlay(alignment: .bottom) {
            HomeRecentProgressBar(item: item)
        }
        .overlay(alignment: .topLeading) {
            if !item.isSong, let label = Self.badgeLabel(for: item.itemType) {
                Text(label)
                    .font(.custom(Typography.fontFamily, size: 9, relativeTo: .caption2).weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.black.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .circular)
                    )
                    .padding(Dimens.spacing12)
            }
        }
        .frame(width: HomeMetrics.episodeCardWidth, height: HomeMetrics.episodeCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .circular))
        .padding(.trailing, HomeMetrics.cardSpacing)
    }

    /// An artist in the wide rail. Artist photos are square, so filling the
    /// 256x144 frame cut the face off. The card keeps the rail's wide shape,
    /// but the whole photo sits on the left at full card height (inset), over
    /// a blurred, darkened copy of itself, with the name beside it.
    private var artistSubtitle: String {
        let subtitle = (item.subtitle ?? "").homeTrimmed
        return subtitle.isEmpty ? String(localized: "Artist") : subtitle
    }

    private var artistWideCard: some View {
        let inset = Dimens.spacing12
        let photoSize = HomeMetrics.episodeCardHeight - inset * 2
        return ZStack {
            ArtworkView(
                url: artworkURL,
                width: HomeMetrics.episodeCardWidth,
                height: HomeMetrics.episodeCardHeight,
                cornerRadius: 0
            )
            .blur(radius: 24)
            .overlay(Color.black.opacity(0.45))
            HStack(alignment: .center, spacing: Dimens.spacing12) {
                ArtworkView(
                    url: artworkURL,
                    width: photoSize,
                    height: photoSize,
                    cornerRadius: Dimens.cornerRadiusSmall
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text((item.title ?? "").homeTrimmed)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                    Text(artistSubtitle)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(inset)
        }
        .overlay(alignment: .bottom) {
            HomeRecentProgressBar(item: item)
        }
        .frame(width: HomeMetrics.episodeCardWidth, height: HomeMetrics.episodeCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .circular))
        .padding(.trailing, HomeMetrics.cardSpacing)
    }

    // MARK: Tap

    private func onTap() {
        switch item.itemType {
        case "companyPlaylist":
            if let entityID = item.entityId {
                coordinator.push(route(playlistID: entityID, isCompany: true))
                return
            }
        case "album", "season":
            if let entityID = item.entityId {
                coordinator.push(route(playlistID: entityID, isCompany: false))
                return
            }
        case "userPlaylist":
            if let entityID = item.entityId {
                coordinator.push(.userPlaylistSongs(playlistID: entityID))
                return
            }
        case "creator":
            if let entityID = item.entityId {
                coordinator.push(.creatorSongs(creatorID: entityID, userPlaylistID: nil))
                return
            }
        default:
            break
        }
        resume()
    }

    private func route(playlistID: String, isCompany: Bool) -> AppRoute {
        .playlistDetail(
            playlistID: playlistID,
            title: item.title ?? "",
            image: item.image,
            imageVariants: item.imageVariants,
            songsCount: nil,
            isCompanyOwned: isCompany,
            creatorID: nil,
            creatorName: nil
        )
    }

    /// Bare song, or a container we could not resolve — resume the track the
    /// server told us this card was left on. The native app holds no local
    /// song cache, so the one track is fetched and played on its own.
    private func resume() {
        guard let songID = item.songId, !isResuming else { return }
        isResuming = true
        let source = HomePlayback.homeAttribution(uiId: uiId)
        let coordinator = coordinator
        Task { @MainActor in
            defer { isResuming = false }
            let repository: any SongRepository = DependencyContainer.current.resolve()
            guard let song = try? await repository.fetchSong(id: songID) else { return }
            HomePlayback.shared.play(song: song, in: [song], source: source, coordinator: coordinator)
        }
    }
}
