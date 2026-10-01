import UIKit

/// Semantic haptic-feedback vocabulary wrapping UIKit's three feedback-
/// generator families (`UISelectionFeedbackGenerator`,
/// `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`).
///
/// Dart triggers a haptic exactly once in the whole app —
/// `HapticFeedback.mediumImpact()` on voice-search start
/// (`lib/widgets/search/voice_search_button.dart:144`) — so `.mediumImpact`
/// below is the one case with a direct Dart call site. The rest of the
/// vocabulary exists ahead of its call sites (voice search itself lands in
/// a later milestone), mirroring UIKit's own complete style/type sets
/// rather than inventing new app-specific semantic names — the same "Dart
/// under-uses a native convention, lean into the fuller native idiom"
/// reasoning `AppSheetContainer`'s drag handle already established in T12.
///
/// Lives under `DesignSystem/Foundations` rather than `Core`: T14 sits in
/// M1 alongside T10-T13, which are all design-system-layer tasks (tokens,
/// glass, components, media), and `Foundations` is the pre-scaffolded,
/// previously-empty home for cross-cutting design-system infrastructure
/// that's neither a token/enum (`Tokens/`) nor a `ViewModifier`
/// (`Modifiers/`) — unlike `Core/Utilities/Clock.swift`, which is a
/// low-level, non-UI, app-wide utility with no design-system connection.
enum HapticFeedback {
    case selection
    case impact(Impact)
    case notification(Notification)

    enum Impact {
        case light, medium, heavy, soft, rigid

        fileprivate var style: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            case .soft: .soft
            case .rigid: .rigid
            }
        }
    }

    enum Notification {
        case success, warning, error

        fileprivate var type: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
    }

    /// Ported 1:1 from Dart's one call site — see this type's doc comment.
    static let mediumImpact = HapticFeedback.impact(.medium)

    /// `UIFeedbackGenerator` and its subclasses are UIKit objects that must
    /// only be touched from the main thread; every SwiftUI view body/action
    /// this is called from already runs on the main actor, so isolating
    /// here adds no friction at real call sites.
    @MainActor
    func trigger() {
        switch self {
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .impact(let style):
            let generator = UIImpactFeedbackGenerator(style: style.style)
            generator.prepare()
            generator.impactOccurred()
        case .notification(let type):
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type.type)
        }
    }
}
