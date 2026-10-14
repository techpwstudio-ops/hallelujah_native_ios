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

    private static let badgeLabels: [String: String] = [
        "companyPlaylist": "Playlist",
        "album": "Album",
        "season": "Season",
        "userPlaylist": "Your list",
        "creator": "Artist",
    ]

    static let coverSize: CGFloat = HomeMetrics.coverSize

    private var artworkURL: URL? { HomeArt.url(item.image, item.imageVariants, .md) }

    var body: some View {
        Group {
            if item.isEpisode {
                wideCard
            } else {
                HomeSquareCard(
                    url: artworkURL,
                    title: (item.title ?? "").homeTrimmed
                )
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
        .overlay(alignment: .topLeading) {
            if !item.isSong, let label = Self.badgeLabels[item.itemType] {
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
