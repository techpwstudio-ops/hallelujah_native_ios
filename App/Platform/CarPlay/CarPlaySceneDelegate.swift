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
/// Known gap vs the Flutter delegate: its `scene(_:continue:)` handled Siri's
/// `INPlayMediaIntent` ("Hey Siri, play <song> in Hallelujah") via a separate
/// SiriIntents extension. That extension doesn't exist in this native app
/// yet, so Siri voice play isn't wired.
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

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        logger.info("CarPlay scene disconnected")
        controller?.stop()
        controller = nil
    }
}
