import UIKit

/// Which way the app may turn. The app is portrait everywhere, on iPhone and iPad alike, except the
/// full-screen podcast video, which holds it in landscape while it is up. `AppDelegate` answers
/// `supportedInterfaceOrientationsFor` from here, so this is the one switch.
///
/// The iPad honours it because Info.plist sets `UIRequiresFullScreen` (an iPad app in Split View
/// has its orientation lock ignored).
@MainActor
enum OrientationLock {
    private static var mask: UIInterfaceOrientationMask = .portrait

    /// What the app delegate reports.
    static var supported: UIInterfaceOrientationMask { mask }

    /// Turns the phone to landscape and holds it there.
    static func landscape() { apply(.landscape, rotateTo: .landscapeRight) }

    /// Turns the phone back to portrait, the app's normal orientation.
    static func portrait() { apply(.portrait, rotateTo: .portrait) }

    private static func apply(_ mask: UIInterfaceOrientationMask, rotateTo target: UIInterfaceOrientationMask) {
        guard self.mask != mask else { return }
        self.mask = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            // Every controller in the presented chain is asked again, so the full-screen cover on top
            // of the player turns too.
            var controller = scene.keyWindow?.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
        }
    }
}
