import SwiftUI

/// Ports `UserPlaylistListItem` / `_CompanyPlaylistSearchRow`
/// (`lib/widgets/playlists/*`): 52pt square cover radius 8, 12pt gap, 16/6
/// padding, title `titleSmall` w500 (capitalised, "Unnamed Playlist"
/// fallback), subtitle `"Playlist • <owner> • <Visibility>"` (company rows:
/// `"Playlist • <app name>"`). Trailing: close button in recent searches,
/// otherwise the `more_vert` content menu.
struct SearchPlaylistRow: View {
    let playlist: SearchPlaylistResult
    var onRemove: (() -> Void)?
    var onMore: (() -> Void)?
    let onTap: () -> Void

    static let coverSize: CGFloat = 52

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(
            path: playlist.image,
            variant: .sm,
            allowedVariants: playlist.imageVariants,
            fallbackName: playlist.title
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if let owner = playlist.ownerName, !owner.isEmpty { parts.append(owner) }
        if playlist.ownerType == .user, let visibility = playlist.visibility {
            parts.append(visibility.parityCapitalized)
        }
        let joined = parts.joined(separator: parityDotSign)
        return joined.isEmpty ? "Playlist" : "Playlist\(parityDotSign)\(joined)"
    }

    var body: some View {
        HStack(spacing: Dimens.spacing12) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.coverSize,
                height: Self.coverSize,
                cornerRadius: Dimens.cornerRadius
            )

            ParityRowText(
                title: playlist.title.map { $0.parityCapitalized } ?? "Unnamed Playlist",
                subtitle: subtitle
            )

            Spacer(minLength: 0)

            if let onRemove {
                ParityCloseButton(action: onRemove)
            } else if let onMore {
                ParityMoreButton(action: onMore)
            }
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
