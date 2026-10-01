import SwiftUI

/// Durations ported from `lib/theme/page_transitions.dart`. That file's own
/// comment explains why its page transition runs at 300ms specifically: the
/// stock Material transition (450ms) "reads as sluggish next to the 300ms the
/// rest of the app's motion uses" — i.e. 300ms is already this app's
/// established "normal" duration, not just a page-transition-specific number.
/// `fast`/`slow` are new (Dart has no wider duration scale defined); T14
/// (Motion and haptics) will add spring presets for the mini/full player
/// expansion specifically, which needs more than a duration.
enum MotionDuration {
    static let fast: TimeInterval = 0.15
    static let normal: TimeInterval = 0.3
    static let slow: TimeInterval = 0.45

    /// The floating tab bar / mini-player dock's show/hide durations —
    /// `AnimationController(duration: 380ms, reverseDuration: 260ms)` in both
    /// `MusicPlayerBottomIos26` and `_AnimatedNavBar`
    /// (`lib/widgets/navigation/our_adaptive_scaffold.dart`). Asymmetric by
    /// design in Dart (hide is faster than show), so kept as two named values
    /// rather than reusing one of the symmetric durations above.
    static let dockShow: TimeInterval = 0.38
    static let dockHide: TimeInterval = 0.26

    /// `AnimatedSize`'s duration in `NoNetworkBanner`
    /// (`lib/widgets/ui/no_network_banner.dart`) — 280ms, distinct from
    /// `normal`'s 300ms, so kept as its own named value rather than rounded
    /// into an existing one.
    static let offlineBanner: TimeInterval = 0.28

    static let allCases: [(name: String, value: TimeInterval)] = [
        ("fast", fast),
        ("normal", normal),
        ("slow", slow),
        ("dockShow", dockShow),
        ("dockHide", dockHide),
        ("offlineBanner", offlineBanner),
    ]
}

enum MotionCurve {
    static let fast = Animation.easeInOut(duration: MotionDuration.fast)
    static let standard = Animation.easeInOut(duration: MotionDuration.normal)
    static let slow = Animation.easeInOut(duration: MotionDuration.slow)

    /// Spring presets for the mini-player -> full-player matched-geometry
    /// expansion (T14), as this file's own comment above already flagged
    /// duration presets alone wouldn't cover. No Dart precedent exists to
    /// port: `Hero` (Flutter's own matched-geometry primitive) is used
    /// elsewhere in the app (`creator_meta_ui.dart`, `hero_wrapper.dart`,
    /// `creator_songs_page.dart`) but never for the mini/full player, which
    /// instead pushes a plain modal route (`music_player_bottom.dart`'s
    /// `NavigationService.pushModal`) with no custom transition at all —
    /// `matchedGeometryEffect` there is a deliberate native-iOS improvement
    /// (the same continuity-morph feel iOS's own system apps use for a
    /// docked bar expanding to full screen), not a port, so these constants
    /// are a judgment call rather than a grounded value.
    ///
    /// `expand` favors a snappy, mostly-critical response (low overshoot) —
    /// appropriate for a large view morphing across the whole screen, where
    /// visible bounce on something this big reads as loose rather than
    /// lively. `collapse` (dismissal) is tuned slightly tighter/faster,
    /// matching the general platform convention that dismissal reads best
    /// as quicker than presentation.
    static let expand = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let collapse = Animation.spring(response: 0.38, dampingFraction: 0.9)

    /// `Curves.easeOutCubic`/`Curves.easeInCubic`, the exact `Cubic` control
    /// points from the Flutter SDK source (`flutter_3.47.3/packages/flutter/
    /// lib/src/animation/curves.dart`) rather than the differently-numbered
    /// CSS/web curve of the same name — same verification T15 already did for
    /// the splash screen's curves. Drives the tab bar / mini-player dock's
    /// show/hide (`MotionDuration.dockShow`/`dockHide`).
    static let dockShow = Animation.timingCurve(0.215, 0.61, 0.355, 1.0, duration: MotionDuration.dockShow)
    static let dockHide = Animation.timingCurve(0.55, 0.055, 0.675, 0.19, duration: MotionDuration.dockHide)

    /// `Curves.easeInOut`, `NoNetworkBanner`'s exact curve for its
    /// `AnimatedSize` show/hide.
    static let offlineBanner = Animation.easeInOut(duration: MotionDuration.offlineBanner)
}
