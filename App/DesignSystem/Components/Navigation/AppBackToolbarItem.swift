import SwiftUI

/// The one custom back button every screen that hides the system back button
/// uses, so they all look alike: a 36pt circle with a chevron. On iOS 26 the
/// system wraps a bare toolbar button in its own glass capsule (which turned
/// this into an oval), so the shared background is switched off and the circle
/// is drawn here.
struct AppBackToolbarItem: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { AppToolbarCircleButton(systemName: "chevron.left", label: "Back", action: action) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { AppToolbarCircleButton(systemName: "chevron.left", label: "Back", action: action) }
        }
    }
}

/// Round 36pt toolbar button — the visual used for back (and matching trailing
/// actions such as the player's "more").
struct AppToolbarCircleButton: View {
    let systemName: String
    let label: String
    var rotation: Angle = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .rotationEffect(rotation)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr(label))
    }
}
