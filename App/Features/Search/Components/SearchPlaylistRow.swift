import SwiftUI

/// A user/company playlist result row. 56pt square cover, matching the size
/// rhythm the other two search rows share.
///
/// Subtitle is `ownerName`, with `visibility.capitalized` appended only for
/// a user-owned playlist — matching `SearchPlaylistResult.visibility`'s own
/// doc comment: a company playlist has no visibility concept, and its row
/// must never render one even if a raw value happened to decode.
struct SearchPlaylistRow: View {
    let playlist: SearchPlaylistResult
    var onRemove: (() -> Void)?
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme
    static let coverSize: CGFloat = 56

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(path: playlist.image, variant: .sm, allowedVariants: playlist.imageVariants)
    }

    private var subtitle: String? {
        guard let ownerName = playlist.ownerName else { return nil }
        if playlist.ownerType == .user, let visibility = playlist.visibility {
            return "\(ownerName) · \(visibility.capitalized)"
        }
        return ownerName
    }

    var body: some View {
        // See `SearchSongRow.body`: `onTapGesture` + `contentShape`, not an
        // outer `Button`, so the trailing remove control stays the row's
        // only real `Button` instead of one nesting inside another.
        HStack(spacing: Spacing.md) {
            ArtworkView(url: resolvedArtwork, width: Self.coverSize, height: Self.coverSize)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(playlist.title ?? "Untitled")
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .lineLimit(1)
                }
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
