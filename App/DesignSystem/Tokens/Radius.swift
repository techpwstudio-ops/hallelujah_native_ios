import CoreGraphics

/// Ported 1:1 from `lib/theme/app_spacing.dart`'s `radius*` constants
/// (`cornerRadius` in `lib/theme/values.dart` is the same value as `md`,
/// duplicated there for one legacy call site — not carried over separately).
enum Radius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16

    /// Not `.infinity` — the Dart source defines this as a fixed 48pt, large
    /// enough to pill any control at the app's standard control heights (see
    /// `Spacing.buttonHeight`/`inputHeight`, both 48–52), not a true capsule
    /// radius for arbitrary-width shapes.
    static let full: CGFloat = 48

    static let allCases: [(name: String, value: CGFloat)] = [
        ("sm", sm),
        ("md", md),
        ("lg", lg),
        ("xl", xl),
        ("full", full),
    ]
}
