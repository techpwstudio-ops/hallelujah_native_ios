import CoreGraphics

/// Ported 1:1 from `lib/theme/app_spacing.dart`'s `AppSpacing` (the scale
/// values, not the `radius*`/`cornerRadius` ones — see `Radius.swift`).
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    static let buttonHeight: CGFloat = 48
    static let inputHeight: CGFloat = 52
    static let minTapTarget: CGFloat = 48

    /// `kBottomNavBarHeight` (`lib/widgets/navigation/our_adaptive_scaffold.dart`).
    static let tabBarHeight: CGFloat = 64
    /// `kMetallicPlayerHeight` (`lib/widgets/player/music_player_bottom_ios26.dart`) —
    /// numerically equal to `tabBarHeight` today but kept as its own constant
    /// since Dart defines them separately too (two names for a coincidence,
    /// not a coupling).
    static let miniPlayerHeight: CGFloat = 64
    /// The floating dock's bottom safe-area padding — `EdgeInsets.only(bottom: 20)`
    /// in `MusicPlayerBottomIos26.build()`, reused for the tab bar pill below it
    /// for the same visual weight (T17; that native tab bar's own margin is
    /// owned by the platform-view bridge, invisible to Dart source).
    static let dockBottomInset: CGFloat = 20

    static let allCases: [(name: String, value: CGFloat)] = [
        ("xs", xs),
        ("sm", sm),
        ("md", md),
        ("lg", lg),
        ("xl", xl),
        ("xxl", xxl),
    ]
}
