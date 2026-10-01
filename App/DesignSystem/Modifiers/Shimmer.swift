import SwiftUI

/// A moving highlight sweep over arbitrary content, the same recipe as
/// Flutter's `Shimmer.fromColors` (`package:shimmer`, used throughout
/// `home_section_shimmer.dart`/`search_shimmer.dart`). Apply once around a
/// WHOLE composed skeleton, not per `SkeletonBox` — `home_section_shimmer.dart`
/// states this cost rule explicitly ("ONE Shimmer PER SECTION, never per
/// card"): `Shimmer` owns an `AnimationController` that ticks every frame, so
/// one per section keeps the count low instead of one per placeholder box.
///
/// No dedicated shimmer color tokens exist in `ColorToken` (T10 didn't add
/// any — Dart's own base/highlight pair there is a hand-picked literal, not a
/// theme color: see that file's own comment on why, "COLOURS ARE LOCAL, NOT
/// FROM THE THEME"). Rather than invent a new asset-catalog pair to match
/// Dart's exact hex literals, this composes the sweep from existing tokens —
/// `textInverse` at low opacity as the moving highlight over whatever base
/// `SkeletonBox`/the wrapped content already draws — so it stays in the token
/// system and adapts to light/dark automatically.
struct ShimmerModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    @State private var phase: CGFloat = -1

    /// Matches `home_section_shimmer.dart`'s `_Shimmer.period` (1400ms) exactly.
    private static let period: TimeInterval = 1.4

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, theme.color(.textInverse).opacity(0.16), .clear],
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

    @Environment(\.appTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.color(.surfaceSecondary))
            .frame(width: width, height: height)
    }
}
