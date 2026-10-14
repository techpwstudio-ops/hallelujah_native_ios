import SwiftUI

/// Ports `LyricsLineItem` (`lib/widgets/player/lyrics_line_item.dart`): one
/// centred transcript line, `titleMedium` w700 / 1.4 height; active and past
/// lines white, future lines white @ 38%; the active line scales to 1.06 and
/// colours animate over 280 ms easeOutCubic. Padding 12 x 8.
struct LyricsLineItem: View {
    let text: String
    let isActive: Bool
    let isPast: Bool
    var onTap: (() -> Void)?

    static let easeOutCubic = Animation.timingCurve(0.215, 0.61, 0.355, 1.0, duration: 0.28)

    var body: some View {
        Text(text)
            .typography(PlayerStyle.lyricsLine)
            .multilineTextAlignment(.center)
            .foregroundStyle(isActive || isPast ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.38))
            .frame(maxWidth: .infinity)
            .scaleEffect(isActive ? 1.06 : 1.0)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .animation(Self.easeOutCubic, value: isActive)
            .animation(Self.easeOutCubic, value: isPast)
    }
}

/// `CustomShadedMask` (`lib/widgets/widgets.dart`): fades the first and last
/// 2% of a scrolling list.
struct LyricsEdgeFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.02),
                .init(color: .black, location: 0.98),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
