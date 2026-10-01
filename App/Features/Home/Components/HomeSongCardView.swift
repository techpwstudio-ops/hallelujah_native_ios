import SwiftUI

/// One card in a `songs`-viewType rail — square (or 16:9 for an episode)
/// cover with a two-line title/subtitle underneath. No pixel-parity
/// requirement applies here (D10 is scoped to splash/auth only), so this is
/// a clean native rail card rather than a port of any one of Dart's several
/// per-viewType song card widgets (`HomeSongRowUi`/`HomeSongTrendingUi`/
/// `HomeEpisodeRowUi`/…) — see T28's Status log for the full scope note.
struct HomeSongCardView: View {
    let song: Song

    @Environment(\.appTheme) private var theme

    static let coverSize: CGFloat = 140

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: song.displayImage,
            variant: .md,
            allowedVariants: song.displayImageVariants
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.coverSize,
                height: song.isEpisode ? Self.coverSize * 9 / 16 : Self.coverSize
            )
            Text(song.title ?? "")
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(1)
            if let subtitle = song.creator?.name ?? song.primaryArtists {
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(1)
            }
        }
        .frame(width: Self.coverSize, alignment: .leading)
    }
}
