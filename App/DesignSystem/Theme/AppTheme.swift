import SwiftUI

/// The single environment-injected entry point onto every design token
/// namespace (`ColorToken`, `Typography`, `Spacing`, `Radius`, `Elevation`,
/// `MotionDuration`). Views read `\.appTheme` from the environment rather
/// than referencing token namespaces directly, so a view can be previewed
/// (or, if ever needed, re-skinned) without call-site changes.
///
/// Deliberately a plain `EnvironmentKey`, not the newer `@Entry` macro:
/// `@Entry` is documented as iOS 18+/Xcode 16 SwiftUI API, and this project's
/// deployment target is 17.0 (D3) — without a build to confirm it back-deploys
/// cleanly, the manual pattern (available since iOS 13) is the safer choice.
struct AppTheme: Sendable {
    static let standard = AppTheme()


    var spacing: Spacing.Type { Spacing.self }
    var radius: Radius.Type { Radius.self }
    var elevation: Elevation.Type { Elevation.self }
    var motionDuration: MotionDuration.Type { MotionDuration.self }

    func color(_ token: ColorToken) -> Color { token.color }
    func font(_ token: TypographyToken) -> Font { token.font }
    func icon(_ token: IconToken) -> Image { token.image }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
