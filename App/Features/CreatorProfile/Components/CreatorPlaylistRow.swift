import SwiftUI

/// Ports `PlaylistListItem` (`lib/widgets/song/playlist_list_item.dart`): a
/// 12/8-padded tile with a 56pt thumbnail (radius 4, `sm`), 14pt gap, title
/// `titleSmall` capitalised ("Untitled Playlist" fallback), 4pt gap, subtitle
/// `bodySmall` white70 — `"<creator> • <n> Songs|Podcasts"`. Tapping opens the
/// album / season (`PlaylistSongPage`). `contentType` (the tab this row is
/// under) picks the noun, as `playlist.type` is the same wire value.
struct CreatorPlaylistRow: View {
    let playlist: Playlist
    let contentType: HomeContentType
    var onTap: () -> Void = {}

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
        var parts: [String] = []
        if case let .creator(_, name) = playlist.owner, let name, !name.isEmpty { parts.append(name) }
        parts.append("\(count) \(noun)")
        return parts.joined(separator: parityDotSign)
    }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.thumbnailSize,
                height: Self.thumbnailSize,
                cornerRadius: Dimens.cornerRadiusSmall
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title.isEmpty ? "Untitled Playlist" : playlist.title.parityCapitalized)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(ParityColor.white70)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Dimens.paddingMedium)
        .padding(.vertical, Dimens.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
