import SwiftUI
import UIKit

/// Gradient themes of `_kGradientThemes` (`show_content_share_sheet.dart`), in
/// Flutter's picker order (dark, crimson, cosmic, forest, ocean). `variantKey`s
/// are Flutter's verbatim (note `forest` = v5, `ocean` = v4).
enum ShareCardTheme: CaseIterable, Hashable, Sendable {
    case dark
    case crimson
    case cosmic
    case forest
    case ocean

    var title: String {
        switch self {
        case .dark: "Dark"
        case .crimson: "Crimson"
        case .cosmic: "Cosmic"
        case .forest: "Forest"
        case .ocean: "Ocean"
        }
    }

    /// Appended to the shared link as `?viewType=` so a recipient's
    /// link-preview/OG-crawler image matches the theme the sharer picked.
    var variantKey: String {
        switch self {
        case .dark: "v1"
        case .crimson: "v2"
        case .cosmic: "v3"
        case .forest: "v5"
        case .ocean: "v4"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .dark: [Color(shareHex: 0x1A1A1A), Color(shareHex: 0x0A0A0A)]
        case .crimson: [Color(shareHex: 0xB71C1C), Color(shareHex: 0x0A0A0A)]
        case .cosmic: [Color(shareHex: 0x6A1B9A), Color(shareHex: 0x0D1B2A)]
        case .forest: [Color(shareHex: 0x1B5E20), Color(shareHex: 0x0A0A0A)]
        case .ocean: [Color(shareHex: 0x0D47A1), Color(shareHex: 0x000000)]
        }
    }

    /// `_GradientTheme.cardBgColor` — the inner card's fill.
    var cardBackground: Color {
        switch self {
        case .dark: Color(shareHex: 0x1D1D1D)
        case .crimson: Color(shareHex: 0x3D0A0A)
        case .cosmic: Color(shareHex: 0x2D0D42)
        case .forest: Color(shareHex: 0x0E3012)
        case .ocean: Color(shareHex: 0x072156)
        }
    }
}

/// `_Portrait1x1Preview` / `_Landscape16x9Preview`: a 20pt-radius card
/// (`cardWidth` x `cardWidth * 4/3`) with a top-to-bottom gradient
/// (first colour -> last colour at 50%) holding an inner `cardBgColor` card
/// (80% of the width, 8pt radius/padding): artwork, bold title, white70
/// subtitle, logo and the upper-cased app name. The drop shadow
/// (first colour @ 50%, blur 24, y 8) is applied by the host, outside the
/// captured bounds, as in Flutter where the `RepaintBoundary` excludes it.
///
/// `resolvedArtwork` is only set for the offscreen copy handed to
/// `ImageRenderer`, which cannot wait for `ArtworkView`'s async load.
struct ShareCardView: View {
    let theme: ShareCardTheme
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    var cardWidth: CGFloat = 300
    var isLandscape: Bool = false
    var resolvedArtwork: UIImage? = nil

    private var cardHeight: CGFloat { cardWidth * 4 / 3 }
    private var artworkWidth: CGFloat { cardWidth * 0.7 }
    private var artworkHeight: CGFloat { isLandscape ? cardWidth * 9 / 16 * 0.7 : cardWidth * 0.7 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.gradientColors[0], theme.gradientColors[1].opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                artwork
                    .frame(width: artworkWidth, height: artworkHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .continuous))
                Spacer().frame(height: Dimens.verticalSpacing)
                VStack(spacing: 0) {
                    Text(title)
                        .font(AccountParity.font(16, .bold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    Text((subtitle ?? "").trimmingCharacters(in: .whitespaces))
                        .font(AccountParity.font(12))
                        .foregroundStyle(AccountParity.white70)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    Spacer().frame(height: Dimens.verticalSpacing)
                    VStack(spacing: Dimens.spacing4) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: Dimens.spacing20, height: Dimens.spacing20)
                            .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .continuous))
                        Text("Hallelujah".uppercased())
                            .font(AccountParity.font(14, .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, isLandscape ? Dimens.spacing4 : 0)
            }
            .padding(Dimens.spacing8)
            .frame(width: cardWidth * 0.8)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous).fill(theme.cardBackground)
            )
            .padding(Dimens.spacing8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.spacing20, style: .continuous))
    }

    @ViewBuilder
    private var artwork: some View {
        if let resolvedArtwork {
            Image(uiImage: resolvedArtwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ArtworkView(url: artworkURL, width: artworkWidth, height: artworkHeight, cornerRadius: Dimens.cornerRadiusSmall)
        }
    }
}

private extension Color {
    init(shareHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
