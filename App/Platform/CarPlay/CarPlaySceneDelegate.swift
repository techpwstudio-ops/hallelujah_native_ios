import CarPlay
import Foundation
import UIKit

/// CarPlay scene/lifecycle entry point. T48 built the plumbing (paired with
/// the `CPTemplateApplicationSceneSessionRoleApplication` entry in
/// `App/Resources/Info.plist`, which is what makes UIKit instantiate this
/// class by its `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate` name when a
/// CarPlay device connects); T49–T52 hand the connected
/// `CPInterfaceController` to `CarPlayController`, which owns every template.
///
/// Ported from the Flutter host's `ios/CarPlaySceneDelegate.swift`
/// (`didConnect`/`didDisconnect`). The `FlutterMethodChannel` bridge that
/// file used has no equivalent here: `CarPlayController` talks to the same
/// repositories and playback objects as the phone UI directly.
///
/// Siri's `INPlayMediaIntent` ("Hey Siri, play <song> in Hallelujah") reaches
/// the CarPlay scene through `scene(_:continue:)` below and is handled by
/// `SiriPlayService`, as in the Flutter delegate. A cold launch where CarPlay
/// is the only scene to connect is covered by the phone scene's
/// `onContinueUserActivity` hook once that scene exists; whether iOS calls
/// `scene(_:continue:)` for a CarPlay-only cold launch is unverified.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let logger = AppLogger(category: .carPlay)

    /// Live only between `didConnect` and `didDisconnect`.
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        logger.info("CarPlay scene connected")
        let controller = CarPlayController(interfaceController: interfaceController)
        self.controller = controller
        controller.start()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let query = SiriPlayService.query(from: userActivity) else { return }
        Task { @MainActor in
            await SiriPlayService().play(query: query)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        logger.info("CarPlay scene disconnected")
        controller?.stop()
        controller = nil
    }
}
