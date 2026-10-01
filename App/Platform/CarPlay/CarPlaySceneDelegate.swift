import CarPlay
import Foundation
import UIKit

/// T48 — CarPlay scene/lifecycle plumbing only. Paired with the
/// `CPTemplateApplicationSceneSessionRoleApplication` entry in
/// `App/Resources/Info.plist` (`UIApplicationSceneManifest`), which is what
/// makes UIKit instantiate this class (by its `$(PRODUCT_MODULE_NAME).
/// CarPlaySceneDelegate` string name) when a CarPlay device connects — see
/// that key's own doc comment for why no phone-scene entry or
/// `AppDelegate`/`GHallelujahApp` change was needed alongside it.
///
/// Ported from the Flutter host's `ios/CarPlaySceneDelegate.swift`
/// (`didConnect`/`didDisconnect` shape only — that file also bridges every
/// template to Dart through a `flutter_carplay`-style `FlutterMethodChannel`,
/// which has no equivalent in this native rewrite, so none of that carried
/// over). Everything content-related — the tab bar, list templates, pushed
/// templates, Now Playing/handoff, and the QA matrix — is explicitly OUT of
/// scope for this task; T49–T53 build directly on top of this file. The root
/// template set in `didConnect` below is a deliberate, clearly-marked
/// placeholder (a single `CPListTemplate` with one "Coming soon" row) whose
/// only job is confirming the app connects and appears in the CarPlay
/// simulator, this task's own Done criterion — it intentionally does not
/// read from `AudioEngine`/`QueueController` or any repository.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let logger = AppLogger(category: .carPlay)

    /// Live only between `didConnect` and `didDisconnect`, matching the
    /// reference delegate's own field. Kept `private` — nothing outside this
    /// file reads it yet; T49 is expected to extend this same type (adding
    /// the real `CPTabBarTemplate` construction) rather than reach in from
    /// elsewhere.
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        logger.info("CarPlay scene connected")
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(Self.makePlaceholderRootTemplate(), animated: false)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        logger.info("CarPlay scene disconnected")
        self.interfaceController = nil
    }

    // MARK: - Placeholder root template (T49 replaces this with the real tab bar)

    /// A single non-interactive "Coming soon" row — nothing more. T49 swaps
    /// this whole function out for `CPTabBarTemplate(templates: [...])`
    /// (Home, Library, Recents, Search) per its own roadmap entry.
    private static func makePlaceholderRootTemplate() -> CPListTemplate {
        let item = CPListItem(
            text: String(localized: "carplay.placeholder.itemText"),
            detailText: String(localized: "carplay.placeholder.detailText")
        )
        let section = CPListSection(items: [item])
        return CPListTemplate(
            title: String(localized: "carplay.placeholder.rootTitle"),
            sections: [section]
        )
    }
}
