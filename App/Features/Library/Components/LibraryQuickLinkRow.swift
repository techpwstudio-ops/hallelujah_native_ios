import SwiftUI
import UIKit

/// Ports `_LibraryItem` (`lib/widgets/creator/library_item_ui.dart`), a
/// `ListTile`: 8pt content padding, a 56pt leading tile (`assets/icons/<asset>.svg`,
/// radius 8 on `#282828`), 16pt title gap, title `titleMedium` w700, subtitle
/// `bodyMedium` w300 (the raw count), min height 72.
///
/// `assetName` is the SVG's catalogue name (`downloads`, `liked_musics`,
/// `liked_episode`, `liked_artists`); until those SVGs are added to the asset
/// catalogue the tile falls back to a white SF Symbol on the same `#282828`
/// square.
struct LibraryQuickLinkRow: View {
    let assetName: String
    let fallbackSymbol: String
    let title: String
    let count: Int
    let action: () -> Void

    private static let titleStyle = TypographyToken(size: 16, weight: .bold, lineHeightMultiple: 1.4)
    private static let subtitleStyle = TypographyToken(size: 14, weight: .light, lineHeightMultiple: 1.5)
    /// `ListTile`'s default subtitle colour in the dark Material 3 theme
    /// (`onSurfaceVariant`).
    private static let subtitleColor = Color(red: 0xCA / 255, green: 0xC4 / 255, blue: 0xD0 / 255)

    var body: some View {
        Button(action: action) {
            HStack(spacing: Dimens.horizontalSpacing) {
                LibraryAssetTile(assetName: assetName, fallbackSymbol: fallbackSymbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typography(Self.titleStyle)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text("\(count)")
                        .typography(Self.subtitleStyle)
                        .foregroundStyle(Self.subtitleColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Dimens.screenPaddingLeft)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The 56pt rounded quick-link tile.
struct LibraryAssetTile: View {
    let assetName: String
    let fallbackSymbol: String

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    ParityColor.darkFill
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .frame(width: Dimens.listItemThumbnailSizeMd, height: Dimens.listItemThumbnailSizeMd)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// `_LibraryItemShimmer`: 56pt tile, 100x14 title bar, 120x12 subtitle bar
/// (8pt gap) on `fillColor`.
struct LibraryQuickLinkSkeleton: View {
    var body: some View {
        HStack(spacing: Dimens.horizontalSpacing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ParityColor.fill)
                .frame(width: Dimens.listItemThumbnailSizeMd, height: Dimens.listItemThumbnailSizeMd)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(ParityColor.fill).frame(width: 100, height: 14)
                Rectangle().fill(ParityColor.fill).frame(width: 120, height: 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Dimens.screenPaddingLeft)
        .frame(minHeight: 72)
    }
}
