import SwiftUI

/// One card in the `recentMixed`-viewType "Continue Your Journey" rail —
/// already-resolved `title`/`subtitle`/`image` from the server, so this
/// renders one card shape regardless of `itemType`. Same "no pixel-parity
/// requirement" scope note as `HomeSongCardView`.
struct HomeRecentItemCardView: View {
    let item: RecentContentItem

    @Environment(\.appTheme) private var theme

    static let coverSize: CGFloat = 140

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(path: item.image, variant: .md, allowedVariants: item.imageVariants)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.coverSize,
                height: item.isEpisode ? Self.coverSize * 9 / 16 : Self.coverSize
            )
            Text(item.title ?? "")
                .typography(Typography.titleSmall)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(1)
            }
        }
        .frame(width: Self.coverSize, alignment: .leading)
    }
}
