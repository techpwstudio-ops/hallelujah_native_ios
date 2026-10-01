import SwiftUI

/// Ports `PlaylistListItem` (`lib/widgets/song/playlist_list_item.dart`): a
/// 56×56 square thumbnail, title, and a "songsCount Songs/Podcasts" subtitle
/// (the creator-name half of Dart's subtitle is dropped — every row here is
/// already scoped to one creator's own profile, so repeating their name on
/// every row would be redundant in a way it isn't on Dart's shared
/// cross-creator playlist list). No `Formater.formatNumber` abbreviation
/// (no native equivalent exists yet) — the plain count is shown instead.
///
/// `contentType` (the tab this row is rendered under) picks the noun rather
/// than `playlist.type`. This was originally a deliberate sidestep of an
/// unresolved ambiguity between two candidate readings of `playlist.type`;
/// T43 has since resolved it with direct evidence (Prisma schema, backend
/// controller, and Dart's own `_SavedItemRow._resolve()`) that `type` is in
/// fact the wire's `SongType` column (`"music"`/`"episode"`) — see
/// `Playlist.swift`'s `isSeason`. That confirms Dart's own
/// `playlist.type == SongType.music.name` check this row was sidestepping
/// would now be portable directly (`playlist.isSeason ? "Podcasts" :
/// "Songs"`), which would also be more accurate than `contentType` for a
/// mixed-type tab. Left as `contentType` here since fixing it is unrelated
/// to T43's own scope (Library) — not revisited by this task.
struct CreatorPlaylistRow: View {
    let playlist: Playlist
    let contentType: HomeContentType

    @Environment(\.appTheme) private var theme

    private static let thumbnailSize: CGFloat = 56

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: playlist.image,
            variant: .sm,
            allowedVariants: playlist.imageVariants
        )
    }

    private var subtitle: String {
        let count = playlist.songsCount ?? 0
        let noun = contentType == .episode ? "Podcasts" : "Songs"
        return "\(count) \(noun)"
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ArtworkView(url: resolvedArtwork, width: Self.thumbnailSize, height: Self.thumbnailSize)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(playlist.title.isEmpty ? "Untitled Playlist" : playlist.title)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .lineLimit(1)
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
    }
}
