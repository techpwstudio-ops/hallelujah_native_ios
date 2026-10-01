import SwiftUI

/// T37 — one row of `QueueView`, porting the row shape `queue_page.dart`
/// itself builds from (`SongListItem` -> `MusicListItem` ->
/// `BaseMediaListTile`, `base_media_list_tile.dart:66-98`): 56×56 artwork,
/// title, genre subtitle (`song.primaryGenreName`) — the same shape
/// `CreatorSongRow` (T30) already established for this exact Dart tile
/// family, not duplicated as a new layout from scratch. The currently
/// playing row gets `BaseMediaListTile`'s own active styling (yellow/bold
/// title) mapped to `.brandPrimary` rather than a literal yellow, matching
/// `AudioRoutePickerView`'s (T35) identical "app accent, not a literal
/// package color" adaptation for `Vx.yellow500`; `queue_page.dart:107-114`'s
/// own extra 8%-white row background for the current song is applied by
/// the parent list (`QueueView`), not this row, since it's a row
/// *container* decoration (`.listRowBackground`), not part of the tile
/// itself. No trailing play/menu controls — `queue_page.dart` explicitly
/// passes `showMenuButton: false, showPlayButton: false` at this call site.
struct QueueSongRow: View {
    let song: Song
    let isCurrent: Bool

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
                    .fontWeight(isCurrent ? .bold : .semibold)
                    .foregroundStyle(isCurrent ? theme.color(.brandPrimary) : theme.color(.textPrimary))
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
        .opacity(isCurrent ? 1 : 0.7)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }
}
