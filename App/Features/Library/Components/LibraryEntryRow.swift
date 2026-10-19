import SwiftUI

/// Ports `LibraryListItem` (`lib/widgets/playlists/library_list_item.dart`):
/// `_SavedItemRow` for saved albums/seasons/company playlists and
/// `UserPlaylistListItem` for the user's own playlists. 56pt thumbnail
/// (radius 8, `sm`), 12pt gap, 8/6 padding, title `titleSmall` w500 white,
/// subtitle `bodySmall` white60 (3pt gap), trailing `more_vert` (32pt, 20pt
/// glyph); a long press opens the same menu.
///
/// Subtitles: `"Album"`/`"Season"` (+ ` • creator`) for creator-owned,
/// `"Playlist"` for company-owned, and `"Playlist"` for the user's own (Dart
/// appends owner name and visibility; `LibraryEntry.userPlaylist` does not
/// carry them).
struct LibraryEntryRow: View {
    let entry: LibraryEntry
    var onMore: () -> Void = {}
    let action: () -> Void

    private static let thumbnailSize: CGFloat = 56

    var body: some View {
        HStack(spacing: Dimens.spacing12) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.thumbnailSize,
                height: Self.thumbnailSize,
                cornerRadius: Dimens.cornerRadius
            )
            ParityRowText(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
            ParityMoreButton(action: onMore)
        }
        .padding(.horizontal, Dimens.screenPaddingLeft)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onLongPressGesture(perform: onMore)
    }

    private var resolvedArtwork: URL? {
        switch entry {
        case let .playlist(playlist):
            return ArtworkURLResolver().resolve(
                path: playlist.image,
                variant: .sm,
                allowedVariants: playlist.imageVariants,
                fallbackName: playlist.title
            )
        case let .userPlaylist(_, title, image, imageVariants, _, _, _):
            // A just-created playlist has no cover until the server composites
            // one; `LoadImage(fallbackName: playlist.title)` shows the letter
            // tile meanwhile.
            return ArtworkURLResolver().resolve(
                path: image,
                variant: .sm,
                allowedVariants: imageVariants,
                fallbackName: title
            )
        }
    }

    private var title: String {
        switch entry {
        case let .playlist(playlist):
            return playlist.title
        case let .userPlaylist(_, title, _, _, _, _, _):
            return title.isEmpty ? String(localized: "Unnamed Playlist") : title.parityCapitalized
        }
    }

    private var subtitle: String {
        switch entry {
        case let .playlist(playlist):
            switch playlist.owner {
            case .company:
                return String(localized: "Playlist")
            case let .creator(_, name):
                let kind = playlist.isSeason ? String(localized: "Season") : String(localized: "Album")
                if let name, !name.isEmpty { return "\(kind)\(parityDotSign)\(name)" }
                return kind
            }
        case let .userPlaylist(_, _, _, _, _, _, detail):
            if let detail, !detail.isEmpty { return "\(String(localized: "Playlist"))\(parityDotSign)\(detail)" }
            return String(localized: "Playlist")
        }
    }
}
