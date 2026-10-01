import SwiftUI

/// One card in a `creators`-viewType rail — circular avatar, centered name
/// underneath. Same "no pixel-parity requirement" scope note as
/// `HomeSongCardView`.
struct HomeCreatorCardView: View {
    let creator: Creator

    @Environment(\.appTheme) private var theme

    static let avatarSize: CGFloat = 88

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: creator.image,
            variant: .md,
            allowedVariants: creator.imageVariants
        )
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.avatarSize,
                height: Self.avatarSize,
                cornerRadius: Self.avatarSize / 2
            )
            Text(creator.name ?? "")
                .typography(Typography.bodySmall)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(width: Self.avatarSize)
    }
}
