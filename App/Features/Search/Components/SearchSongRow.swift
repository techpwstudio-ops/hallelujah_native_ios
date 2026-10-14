import SwiftUI

/// A music/episode result row — search results, top result, and recent
/// searches all use this same shape. Same 56pt-thumbnail layout as
/// `CreatorSongRow` (`CreatorProfile`), duplicated rather than shared: that
/// type belongs to a different, already-finished feature, its subtitle
/// formula is different (genre, not creator), and it has no tap/remove
/// affordance — three lines of layout aren't worth reaching across features
/// for.
///
/// Subtitle is `creator?.name ?? primaryArtists`, matching
/// `HomeSongCardView`'s own convention (no Dart grounding specific to
/// search's own song row subtitle was found, so this defers to that
/// already-vetted sibling rather than inventing a new formula). No trailing
/// play/menu control, same scope cut `CreatorSongRow` already made — the
/// row itself is the tap target.
struct SearchSongRow: View {
    let song: Song
    var onRemove: (() -> Void)?
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme
    static let thumbnailSize: CGFloat = 56

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(path: song.displayImage, variant: .sm, allowedVariants: song.displayImageVariants)
    }

    private var subtitle: String? {
        song.creator?.name ?? song.primaryArtists
    }

    var body: some View {
        // Not an outer `Button` (every sibling row here used to be one): a
        // `Button` nested inside another `Button`'s label has no precedent
        // anywhere else in the app and is a real hit-testing/accessibility
        // hazard — `onTapGesture` + `contentShape` keeps the trailing
        // remove control as the row's only actual `Button`.
        HStack(spacing: Spacing.md) {
            ArtworkView(url: resolvedArtwork, width: Self.thumbnailSize, height: Self.thumbnailSize)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title ?? "Untitled")
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
            } else {
                SongMenuButton(song: song)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
