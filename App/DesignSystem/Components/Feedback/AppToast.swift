import SwiftUI

/// A single toast to display. Mirrors `showSnackBarToast`
/// (`lib/helpers/show_toast_or_snackbar.dart`), which — despite accepting
/// `seconds`/`margin`/`onUndo` parameters — only ever forwards `message` to
/// `Fluttertoast.showToast`; the rest are dead parameters never passed
/// through, and the commented-out `SnackBar` alternative beneath it is
/// unreachable. So the only real, load-bearing behavior to port is: one
/// plain message, dark fill, white text, `Toast.LENGTH_LONG` duration
/// (~3.5s). No undo action, no custom margin, no per-call duration exist in
/// the live Dart behavior, so none are added here.
struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// Presents toasts app-wide. One toast on screen at a time, same as
/// `Fluttertoast` — a second `show` while one is visible replaces it rather
/// than queuing, matching the plugin's own single-toast behavior.
@Observable
@MainActor
final class ToastCenter {
    private(set) var current: ToastMessage?

    /// `Toast.LENGTH_LONG`, the `toastLength` `showSnackBarToast` always
    /// passes (its own `seconds` parameter is dead code — see above).
    private static let duration: TimeInterval = 3.5

    private var dismissTask: Task<Void, Never>?

    /// Explicit and `nonisolated` so `ToastCenterKey.defaultValue` below can
    /// construct one from the `EnvironmentKey` protocol's nonisolated static
    /// context — the implicit init Swift would otherwise synthesize inherits
    /// the class's `@MainActor` isolation, which a nonisolated caller can't
    /// invoke under Swift 6 strict concurrency. Safe because it only assigns
    /// the two stored properties' trivial defaults, touching no isolated state.
    nonisolated init() {}

    func show(_ text: String) {
        dismissTask?.cancel()
        let message = ToastMessage(text: text)
        current = message
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled, self?.current?.id == message.id else { return }
            self?.current = nil
        }
    }
}

private struct ToastCenterKey: EnvironmentKey {
    static let defaultValue = ToastCenter()
}

extension EnvironmentValues {
    var toastCenter: ToastCenter {
        get { self[ToastCenterKey.self] }
        set { self[ToastCenterKey.self] = newValue }
    }
}

/// Renders the active toast as a floating pill pinned to the bottom safe
/// area — `Fluttertoast`'s default gravity/position on iOS — over
/// `darkFillColor`/`white` (`ColorTheme.darkFillColor` = the same hex as
/// `surfaceSecondary`'s dark-mode value; see `Shimmer.swift` for the same
/// "compose from existing tokens instead of a new literal" reasoning),
/// so it adapts to light mode automatically instead of staying hardcoded
/// dark the way the Flutter toast always is.
private struct ToastOverlay: View {
    let message: ToastMessage?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack {
            Spacer()
            if let message {
                Text(message.text)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(theme.color(.surfaceSecondary))
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MotionCurve.standard, value: message?.id)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Installs a `ToastCenter` into the environment and overlays its
    /// active toast. Apply near the app's root and on screens presented in their own layer.
    func toastOverlay() -> some View {
        modifier(ToastOverlayModifier())
    }
}

extension ToastCenter {
    /// The single app-wide center. Screens that pop right after showing a
    /// toast (Profile → "Profile updated successfully") still have it
    /// rendered, because an overlay also lives on the shell, not only on
    /// the screen. Every `.toastOverlay()` shares it; a sheet gets its own
    /// overlay layer so toasts aren't hidden behind it, and the identical
    /// pill drawn by an outer layer underneath is invisible.
    static let shared = ToastCenter()
}

private struct ToastOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.toastCenter, ToastCenter.shared)
            .overlay {
                ToastOverlay(message: ToastCenter.shared.current)
            }
    }
}
