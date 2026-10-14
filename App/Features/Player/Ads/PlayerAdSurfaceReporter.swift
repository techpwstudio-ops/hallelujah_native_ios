import SwiftUI

/// Tells `PlayerAdController` that a view which can draw the player's image ad is
/// on screen (`PlayerAdCubit.surfaceShown` / `surfaceHidden`).
///
/// The clock only runs while at least one surface is on screen and the app is in
/// the foreground — without that an ad would use up its 30 seconds on a screen
/// nobody is looking at, and the server would have reserved the advertiser's
/// budget for it anyway. A surface counts while it is in the hierarchy, the scene
/// is active, and `isEnabled` (e.g. nothing is covering it) holds.
private struct PlayerAdSurfaceReporter: ViewModifier {
    let controller: PlayerAdController
    let isEnabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var token = UUID()
    @State private var isInHierarchy = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isInHierarchy = true
                report(inHierarchy: true, enabled: isEnabled, phase: scenePhase)
            }
            .onDisappear {
                isInHierarchy = false
                report(inHierarchy: false, enabled: isEnabled, phase: scenePhase)
            }
            .onChange(of: isEnabled) { _, enabled in
                report(inHierarchy: isInHierarchy, enabled: enabled, phase: scenePhase)
            }
            .onChange(of: scenePhase) { _, phase in
                report(inHierarchy: isInHierarchy, enabled: isEnabled, phase: phase)
            }
    }

    private func report(inHierarchy: Bool, enabled: Bool, phase: ScenePhase) {
        if inHierarchy, enabled, phase == .active {
            controller.surfaceShown(token)
        } else {
            controller.surfaceHidden(token)
        }
    }
}

extension View {
    /// Marks this view as a surface the player's image ad can be drawn on.
    func playerAdSurface(_ controller: PlayerAdController, isEnabled: Bool = true) -> some View {
        modifier(PlayerAdSurfaceReporter(controller: controller, isEnabled: isEnabled))
    }
}
