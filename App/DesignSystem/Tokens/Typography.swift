import SwiftUI

/// One entry in the type scale. `lineHeightMultiple` mirrors Flutter's
/// `TextStyle.height` (a multiplier of font size); SwiftUI has no direct
/// equivalent, so `lineSpacing` below approximates it as
/// `size * (multiple - 1)` extra spacing — the same approximation most
/// SwiftUI design systems use when porting a Flutter/CSS-style line-height.
/// It will not reproduce Flutter's exact line box, only its visual rhythm.
struct TypographyToken: Sendable {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeightMultiple: CGFloat
    let tracking: CGFloat

    init(size: CGFloat, weight: Font.Weight, lineHeightMultiple: CGFloat, tracking: CGFloat = 0) {
        self.size = size
        self.weight = weight
        self.lineHeightMultiple = lineHeightMultiple
        self.tracking = tracking
    }

    /// D12: the Flutter app pins "Helvetica Neue" on iOS (`lib/theme/text.dart`
    /// `fontFamily`), so the native app renders the same face. It scales with
    /// Dynamic Type relative to the body style, as the system font did.
    var font: Font { .custom(Typography.fontFamily, size: size, relativeTo: .body).weight(weight) }
    var lineSpacing: CGFloat { size * (lineHeightMultiple - 1) }
}

/// Type scale ported from `lib/theme/app_text_styles.dart` (`AppTextStyles`):
/// every size, weight, and line-height multiple matches the Dart source.
///
/// One deliberate deviation, recorded as D11 in `progress.md`: the Dart app
/// pins its font family to "Helvetica Neue" on iOS (`lib/theme/text.dart`)
/// rather than using the system font. This scale uses `Font.system`, i.e. San
/// Francisco, instead — this task is establishing the *native* design system
/// the roadmap calls for (D10's pixel-parity rule is scoped only to the
/// splash and auth screens, not the whole app), and San Francisco is what
/// Dynamic Type, SF Symbols, and every system control already assume.
enum Typography {
    /// PostScript family name shipped with iOS.
    static let fontFamily = "HelveticaNeue"

    static let displayLarge = TypographyToken(size: 32, weight: .bold, lineHeightMultiple: 1.2)
    static let headlineLarge = TypographyToken(size: 28, weight: .bold, lineHeightMultiple: 1.3)
    static let headlineMedium = TypographyToken(size: 24, weight: .semibold, lineHeightMultiple: 1.3)
    static let titleLarge = TypographyToken(size: 20, weight: .semibold, lineHeightMultiple: 1.4)
    static let titleMedium = TypographyToken(size: 16, weight: .semibold, lineHeightMultiple: 1.4)
    static let titleSmall = TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.4)
    static let bodyLarge = TypographyToken(size: 16, weight: .regular, lineHeightMultiple: 1.5)
    static let bodyMedium = TypographyToken(size: 14, weight: .regular, lineHeightMultiple: 1.5)
    static let bodySmall = TypographyToken(size: 12, weight: .regular, lineHeightMultiple: 1.5)
    static let labelLarge = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1, tracking: 0.1)
    static let labelMedium = TypographyToken(size: 12, weight: .medium, lineHeightMultiple: 1, tracking: 0.1)
    static let labelSmall = TypographyToken(size: 11, weight: .regular, lineHeightMultiple: 1, tracking: 0.5)

    static let allCases: [(name: String, token: TypographyToken)] = [
        ("Display Large", displayLarge),
        ("Headline Large", headlineLarge),
        ("Headline Medium", headlineMedium),
        ("Title Large", titleLarge),
        ("Title Medium", titleMedium),
        ("Title Small", titleSmall),
        ("Body Large", bodyLarge),
        ("Body Medium", bodyMedium),
        ("Body Small", bodySmall),
        ("Label Large", labelLarge),
        ("Label Medium", labelMedium),
        ("Label Small", labelSmall),
    ]
}

extension View {
    func typography(_ token: TypographyToken) -> some View {
        font(token.font)
            .lineSpacing(token.lineSpacing)
            .tracking(token.tracking)
    }
}
