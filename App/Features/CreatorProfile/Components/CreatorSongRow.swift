import SwiftUI

/// Ports `MusicListItem`/`EpisodeListItem`'s shared shape
/// (`lib/widgets/song/base_media_list_tile.dart`): a 56×56 thumbnail, title,
/// and a one-line subtitle (`song.primaryGenreName`). No trailing
/// play/menu controls (`MediaTrailingSection`) — those need a song action
/// sheet, which doesn't exist yet. `onTap` defaults to a no-op; T42's
/// `GenreSongsView` is the first to wire a real tap-to-play handler through.
/// Deliberately `.onTapGesture`, not `Button` — a `Button` wrapper would add
/// the system "Button" accessibility trait and press-down animation to the 3
/// existing, non-interactive callers (`CreatorProfileView`/`SectionDetailView`/
/// `PlaylistDetailView`) too, which is a real regression for a no-op tap.
struct CreatorSongRow: View {
    let song: Song
    var onTap: () -> Void = {}

    @Environment(\.appTheme) private var theme

    private static let thumbnailSize: CGFloat = 56

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: song.displayImage,
            variant: .sm,
            allowedVariants: song.displayImageVariants
        )
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ArtworkView(url: resolvedArtwork, width: Self.thumbnailSize, height: Self.thumbnailSize)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title ?? "Untitled")
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                if let genre = song.primaryGenre?.name {
                    Text(genre)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.textSecondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
