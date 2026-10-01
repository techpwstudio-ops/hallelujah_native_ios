import SwiftUI

/// Fixed literal colors ported directly from `lib/theme/colors.dart`, for the
/// D10 pixel-parity requirement on the auth screens (T21-T24) — deliberately
/// NOT routed through the themed `ColorToken` system, which answers
/// light/dark differently than these Dart literals do. Same reasoning
/// `SplashView` documents for its own `Color.black` literal: the Flutter
/// screens these port are black/`fillColor` regardless of the system's
/// light/dark setting, so the native ports have to be too.
enum AuthColors {
    /// `backgroundColor` / `ColorTheme.dark` (`lib/theme/colors.dart`) —
    /// both `Colors.black`.
    static let background = Color.black
    /// `fillColor` (`Color(0xFF1D1D1D)`).
    static let fill = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1D / 255)
    /// `defaultPinTheme`'s `focusedPinTheme` border
    /// (`Color.fromRGBO(114, 178, 238, 1)`).
    static let focusedBorder = Color(red: 114 / 255, green: 178 / 255, blue: 238 / 255)
    /// `ColorTheme.hintColor` (`Color(0xFF808080)`).
    static let hint = Color(red: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255)
    /// `AppTextField._focusedBorder` (`lib/widgets/app_text_field.dart`) —
    /// `Colors.white24`, a different literal from `focusedBorder` above
    /// (that one's Pinput's OTP-box border, this is the generic form
    /// field's — two genuinely different Dart constants, not a duplicate).
    static let textFieldFocusedBorder = Color.white.opacity(0.24)

    // MARK: T25 — `ColorTheme` (`lib/theme/colors.dart`), the language picker's
    // monochrome accent set plus the generic text/fill opacities it builds on.

    /// `ColorTheme.secondaryTextColor` (`white.withOpacity(0.70)`).
    static let secondaryText = Color.white.opacity(0.70)
    /// `ColorTheme.tertiaryTextColor` (`white.withOpacity(0.47)`).
    static let tertiaryText = Color.white.opacity(0.47)
    /// `ColorTheme.white12`.
    static let white12 = Color.white.opacity(0.12)
    /// `ColorTheme.white24` — same literal as `textFieldFocusedBorder` above,
    /// named separately since this one tints text/icons, not a border.
    static let white24 = Color.white.opacity(0.24)
    /// `ColorTheme.darkFillColor` (`Color(0xFF282828)`).
    static let darkFill = Color(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    /// `ColorTheme.accentSurface` (`Color(0xFF2E2E2E)`) — tinted surface
    /// behind an accent badge or the rule banner icon.
    static let accentSurface = Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x2E / 255)
    /// `ColorTheme.accentBorder` (`Color(0xFF7C7C7C)`) — a selected language
    /// card's border.
    static let accentBorder = Color(red: 0x7C / 255, green: 0x7C / 255, blue: 0x7C / 255)
    /// `ColorTheme.accentFill` (`Color(0xFF232323)`) — a selected language
    /// card's fill.
    static let accentFill = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x23 / 255)
    /// `ColorTheme.accentActionBg` — the language screen's primary-action
    /// gradient, white falling off slightly at the trailing edge.
    static let accentActionGradient = LinearGradient(
        colors: [Color.white, Color(red: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255)],
        startPoint: .leading,
        endPoint: .trailing
    )
}
