import SwiftUI

/// One row of the queue: `SongListItem` -> `MusicListItem` ->
/// `BaseMediaListTile` as `queue_page.dart` builds it. 12 x 8 padding,
/// 56pt-high artwork (`Dimens.listItemThumbnailSizeMd`, width scaled by the
/// song's aspect ratio) with a 4pt radius, 14pt gap, `titleMedium` title
/// (w600, bold + yellow while it is the playing song), 4pt gap, genre in
/// `bodySmall` white @ 70%. Non-current rows are dimmed to 70% by the list.
struct QueueSongRow: View {
    let song: Song
    let isCurrent: Bool

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: song.displayImage,
            variant: .sm,
            allowedVariants: song.displayImageVariants
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(
                url: resolvedArtwork,
                width: Dimens.listItemThumbnailSizeMd * CGFloat(song.displayAspectRatio),
                height: Dimens.listItemThumbnailSizeMd,
                cornerRadius: Dimens.cornerRadiusSmall
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title ?? "")
                    .typography(isCurrent ? PlayerStyle.titleMediumBold : PlayerStyle.titleMediumSemibold)
                    .foregroundStyle(isCurrent ? PlayerStyle.activeYellow : PlayerStyle.white)
                    .lineLimit(1)
                Text(song.primaryGenre?.name ?? "")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
