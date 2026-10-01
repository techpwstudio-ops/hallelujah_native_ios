import SwiftUI
import UIKit

/// Client-rendered "story card" theme, matching Dart's own default share
/// preview (`RenderRepaintBoundary`, also client-rendered — the server's
/// `?themeVariant=` re-composite is only ever fetched by a recipient's
/// link-preview crawler, never by the sharing app itself). Hex pairs and
/// `variantKey`s are the Flutter `ShareThemeType` gradients verbatim; note
/// `forest` is `v5`, not sequential with the others.
enum ShareCardTheme: CaseIterable, Hashable, Sendable {
    case dark
    case crimson
    case cosmic
    case ocean
    case forest

    var title: String {
        switch self {
        case .dark: "Dark"
        case .crimson: "Crimson"
        case .cosmic: "Cosmic"
        case .ocean: "Ocean"
        case .forest: "Forest"
        }
    }

    /// Appended to the shared link as `?viewType=` so a recipient's
    /// link-preview/OG-crawler image matches the theme the sharer picked.
    var variantKey: String {
        switch self {
        case .dark: "v1"
        case .crimson: "v2"
        case .cosmic: "v3"
        case .ocean: "v4"
        case .forest: "v5"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .dark: [Color(shareHex: 0x1A1A1A), Color(shareHex: 0x0A0A0A)]
        case .crimson: [Color(shareHex: 0xB71C1C), Color(shareHex: 0x0A0A0A)]
        case .cosmic: [Color(shareHex: 0x6A1B9A), Color(shareHex: 0x0D1B2A)]
        case .ocean: [Color(shareHex: 0x0D47A1), Color(shareHex: 0x000000)]
        case .forest: [Color(shareHex: 0x1B5E20), Color(shareHex: 0x0A0A0A)]
        }
    }
}

/// The square gradient preview card shown in `ShareSheetView` and captured
/// via `ImageRenderer` for Save-to-Photos / "More" share.
struct ShareCardView: View {
    let theme: ShareCardTheme
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    /// Set only for the offscreen copy `ShareSheetView` builds right before
    /// handing this view to `ImageRenderer`: `ImageRenderer.uiImage` reads
    /// synchronously, so it can't wait on `ArtworkView`'s own async `.task`
    /// load the way the onscreen preview (this parameter left `nil`) can.
    var resolvedArtwork: UIImage? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            artwork
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .typography(Typography.titleMedium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            Text("Hallelujah")
                .typography(Typography.labelMedium)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, Spacing.lg)
        }
        .frame(width: 300, height: 300)
        .background(
            LinearGradient(
                colors: theme.gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    @ViewBuilder
    private var artwork: some View {
        if let resolvedArtwork {
            Image(uiImage: resolvedArtwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ArtworkView(url: artworkURL, width: 200, height: 200, cornerRadius: Radius.lg)
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
