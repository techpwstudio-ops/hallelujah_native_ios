import SwiftUI

/// Ports `CreatorSearchItem` (`lib/widgets/creator/artist_search_item.dart`):
/// 52pt circular avatar, 12pt gap, 16/6 padding, title `titleSmall` w500
/// white, subtitle `"Artist • N followers"` (always plural, as Dart prints
/// it) in `bodySmall` white60.
struct SearchCreatorRow: View {
    let creator: SearchCreatorResult
    var onRemove: (() -> Void)?
    let onTap: () -> Void

    static let avatarSize: CGFloat = 52

    private var resolvedArtwork: URL? {
        ArtworkURLResolver().resolve(path: creator.image, variant: .sm, allowedVariants: creator.imageVariants, fallbackName: creator.name)
    }

    private var subtitle: String {
        "\(String(localized: "Artist"))\(parityDotSign)\(String(localized: "\(creator.followersCount ?? 0) followers"))"
    }

    var body: some View {
        HStack(spacing: Dimens.spacing12) {
            ArtworkView(
                url: resolvedArtwork,
                width: Self.avatarSize,
                height: Self.avatarSize,
                cornerRadius: Self.avatarSize / 2
            )

            ParityRowText(title: creator.name ?? "", subtitle: subtitle)

            Spacer(minLength: 0)

            if let onRemove {
                ParityCloseButton(action: onRemove)
            }
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
