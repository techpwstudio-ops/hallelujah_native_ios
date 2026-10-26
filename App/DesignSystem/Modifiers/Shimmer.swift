import SwiftUI

/// A moving highlight sweep over arbitrary content, the same recipe as
/// Flutter's `Shimmer.fromColors` (`package:shimmer`, used throughout
/// `home_section_shimmer.dart`/`search_shimmer.dart`). Apply once around a
/// WHOLE composed skeleton, not per `SkeletonBox` — `home_section_shimmer.dart`
/// states this cost rule explicitly ("ONE Shimmer PER SECTION, never per
/// card"): `Shimmer` owns an `AnimationController` that ticks every frame, so
/// one per section keeps the count low instead of one per placeholder box.
///
/// Colours are Flutter's literal dark pair (`SkeletonBox.base` under a
/// `highlight` band), not theme tokens: the old token mix drew a flat grey
/// that testers read as a blank image.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    /// The sweep over `SkeletonBox`'s `fillColor`: `search_shimmer.dart`'s
    /// `Shimmer.fromColors(baseColor: fillColor, highlightColor:
    /// darkFillColor)` pair, lifted a little so it reads on an OLED black
    /// background. Dark only, like the app.
    static let highlight = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3A / 255)

    /// Matches `home_section_shimmer.dart`'s `_Shimmer.period` (1400ms) exactly.
    private static let period: TimeInterval = 1.4

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Self.highlight, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width)
                    .offset(x: phase * proxy.size.width)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

/// A single filled rounded-rect placeholder — the shimmer system's only
/// visual primitive, matching Dart's `_Box`. Compose several into a layout
/// (mirroring `_Rail`/`_CoverCard`/`_TextLine` in `home_section_shimmer.dart`),
/// then wrap the whole composition in one `.shimmer()`.
struct SkeletonBox: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = Radius.sm

    /// `ColorTheme.fillColor` (0xFF1D1D1D), the Flutter shimmer's base —
    /// not the lighter grey `surfaceSecondary` these boxes used to draw.
    static let base = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1D / 255)

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Self.base)
            .frame(width: width, height: height)
    }
}
