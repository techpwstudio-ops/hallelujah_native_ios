import SwiftUI

/// Artwork URL shorthand used by every Home card.
enum HomeArt {
    static func url(_ path: String?, _ variants: String?, _ variant: ImageVariant) -> URL? {
        ArtworkURLResolver().resolve(path: path, variant: variant, allowedVariants: variants)
    }
}

extension Song {
    /// `canShowSong` (`lib/helpers/song_requirement.dart`). Status fields the
    /// v2 payload may omit are treated as "fine" rather than "hidden", so an
    /// absent field cannot blank a whole rail.
    var isHomeShowable: Bool {
        guard let title, !title.isEmpty else { return false }
        if let songStatus, songStatus != "public" { return false }
        if let reviewStatus, reviewStatus != "accepted" { return false }
        if let releaseDate, releaseDate > Date() { return false }
        return true
    }
}

/// One card in a `songs`/`recent_songs`/`recommended`-rail: `HomeSongItemUi`
/// (98 square cover, radius 4, `md` variant, two-line title) for music and
/// `HomeEpisodeItemUi` (256x144 16:9 card with a bottom scrim, a two-line
/// white title and a 28pt play ring) for podcasts. Tapping plays the rail's
/// list as `PlayerType.home` with the section uiId as the player id.
struct HomeSongCardView: View {
    let song: Song
    let songs: [Song]
    let uiId: String
    var isEpisode = false

    @Environment(AppNavigationCoordinator.self) private var coordinator

    static let coverSize: CGFloat = HomeMetrics.coverSize

    var body: some View {
        Group {
            if isEpisode {
                episodeCard
            } else {
                HomeSquareCard(
                    url: HomeArt.url(song.image, song.imageVariants, .md),
                    title: song.title ?? ""
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HomePlayback.shared.play(
                song: song,
                in: songs,
                source: HomePlayback.homeAttribution(uiId: uiId),
                coordinator: coordinator
            )
        }
    }

    private var episodeCard: some View {
        ZStack(alignment: .bottom) {
            ArtworkView(
                url: HomeArt.url(song.image, song.imageVariants, .md),
                width: HomeMetrics.episodeCardWidth,
                height: HomeMetrics.episodeCardHeight,
                cornerRadius: 0
            )
            LinearGradient(gradient: HomeColors.episodeScrim, startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: Dimens.spacing12) {
                Text((song.title ?? "").homeTrimmed)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HomePlayPauseIcon(songID: song.id, size: 28)
            }
            .padding(Dimens.spacing16)
        }
        .frame(width: HomeMetrics.episodeCardWidth, height: HomeMetrics.episodeCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .circular))
        .padding(.trailing, HomeMetrics.cardSpacing)
    }
}
