import SwiftUI

/// A creator/artist result row. Circular 56pt avatar, matching the size
/// rhythm `SearchSongRow`/`SearchPlaylistRow` share, using the
/// `size / 2` corner-radius idiom `HomeCreatorCardView` establishes for a
/// true circle (`Radius.full` alone isn't big enough at this size).
///
/// Subtitle is "Artist · N followers" — grounded in `artist_search_item.dart`.
struct SearchCreatorRow: View {
    let creator: SearchCreatorResult
    var onRemove: (() -> Void)?
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme
    static let avatarSize: CGFloat = 56

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(path: creator.image, variant: .sm, allowedVariants: creator.imageVariants)
    }

    private var subtitle: String {
        let count = creator.followersCount ?? 0
        return "Artist · \(count) follower\(count == 1 ? "" : "s")"
    }

    var body: some View {
        // See `SearchSongRow.body`: `onTapGesture` + `contentShape`, not an
        // outer `Button`, so the trailing remove control stays the row's
        // only real `Button` instead of one nesting inside another.
        HStack(spacing: Spacing.md) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.avatarSize,
                height: Self.avatarSize,
                cornerRadius: Self.avatarSize / 2
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(creator.name ?? "Untitled")
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let onRemove {
                Button(action: onRemove) {
                    theme.icon(.close)
                        .foregroundStyle(theme.color(.textTertiary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
