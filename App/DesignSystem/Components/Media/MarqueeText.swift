import SwiftUI

/// Auto-scrolling single-line text for titles/subtitles that don't fit their
/// box. Ports `MyMarquee` (`lib/widgets/player/morque.dart`): it measures
/// with a `TextPainter` whether the text already fits and, if so, renders a
/// plain `Text` with no animation at all — mirrored here with a
/// `PreferenceKey` width measurement instead of `TextPainter`, but the same
/// "don't animate text that already fits" behavior. When it doesn't fit, it
/// loop-scrolls using the `Marquee` package's exact configured constants,
/// read directly from that file: `scrollSpeed: 50.0` (pt/s), `height: 24.0`,
/// `blankSpace: 40.0` (gap between the looping copies),
/// `pauseAfterRound: 1s`, `fadingEdgeStartFraction`/`EndFraction: 0.05`.
///
/// One approximation: `Marquee` also configures separate 400ms
/// `accelerationDuration`/`decelerationDuration` ramps either side of the
/// constant-velocity leg — an internal detail of that third-party package,
/// not something its Dart call site (or this file) can reproduce tick-for-
/// tick. `.easeInOut` over the whole scroll leg approximates the same
/// "ease into and out of the scroll" shape without claiming to match it
/// exactly.
struct MarqueeText: View {
    let text: String
    var typography: TypographyToken = Typography.bodyMedium
    var color: Color? = nil
    /// Dart's `MyMarquee` also takes an explicit `height:` per call site
    /// (`morque.dart`'s own constructor param, not a fixed constant) — T34's
    /// mini player needs an 18pt slot rather than this type's own default
    /// 24, to match `music_player_bottom_ios26.dart:312`'s `MyMarquee(height: 18, ...)`.
    var height: CGFloat = 24

    @Environment(\.appTheme) private var theme
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private static let velocity: CGFloat = 50
    private static let blankSpace: CGFloat = 40
    private static let pauseAfterRound: TimeInterval = 1
    private static let edgeFadeFraction: CGFloat = 0.05

    private var resolvedColor: Color { color ?? theme.color(.textPrimary) }
    private var fitsWithoutScrolling: Bool { containerWidth == 0 || textWidth <= containerWidth }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if fitsWithoutScrolling {
                    label
                } else {
                    HStack(spacing: Self.blankSpace) {
                        label
                        label
                    }
                    .offset(x: offset)
                    .mask(edgeFadeMask)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in containerWidth = newValue }
        }
        .frame(height: height)
        .clipped()
        .task(id: scrollTaskID) {
            guard !fitsWithoutScrolling else { return }
            await runScrollLoop()
        }
    }

    private var scrollTaskID: String { "\(text)|\(fitsWithoutScrolling)|\(Int(containerWidth))" }

    private var label: some View {
        Text(text)
            .typography(typography)
            .foregroundStyle(resolvedColor)
            .lineLimit(1)
            .fixedSize()
            .measureWidth($textWidth)
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: Self.edgeFadeFraction),
                .init(color: .black, location: 1 - Self.edgeFadeFraction),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func runScrollLoop() async {
        let cycleDistance = textWidth + Self.blankSpace
        guard cycleDistance > 0 else { return }
        let scrollDuration = TimeInterval(cycleDistance / Self.velocity)

        offset = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.pauseAfterRound))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: scrollDuration)) {
                offset = -cycleDistance
            }
            try? await Task.sleep(for: .seconds(scrollDuration))
            guard !Task.isCancelled else { return }

            offset = 0 // snap back with no animation, then pause and repeat
        }
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func measureWidth(_ binding: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self) { binding.wrappedValue = $0 }
    }
}
