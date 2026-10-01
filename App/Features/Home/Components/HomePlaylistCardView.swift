import SwiftUI

/// One card in a `companyPlaylists`/`aiPlaylist`/`similarPlaylist`/
/// `singleCompanyPlaylist`/`playlists`-viewType rail — square cover, title,
/// and a song-count subtitle. Same "no pixel-parity requirement" scope note
/// as `HomeSongCardView`. `similarPlaylist`'s seed row (`playlist.isSeed`)
/// draws no differently here — the "More Like X" custom header treatment
/// Dart gives it is a deferred scope cut, noted in T28's Status log.
struct HomePlaylistCardView: View {
    let playlist: Playlist

    @Environment(\.appTheme) private var theme

    static let coverSize: CGFloat = 140

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: playlist.image,
            variant: .md,
            allowedVariants: playlist.imageVariants
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ArtworkView(url: resolvedArtwork, width: Self.coverSize, height: Self.coverSize)
            Text(playlist.title)
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(1)
            if let songsCount = playlist.songsCount {
                Text("\(songsCount) songs")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(1)
            }
        }
        .frame(width: Self.coverSize, alignment: .leading)
    }
}
