import GoogleSignIn
import SwiftUI
import UIKit

@main
struct GHallelujahApp: App {
    // T46 — the only way a background `URLSession` (`DownloadEngine`) reaches
    // `application(_:handleEventsForBackgroundURLSession:completionHandler:)`;
    // see `AppDelegate`'s own doc comment.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppComposition.installRuntime()
    }

    var body: some Scene {

        WindowGroup {
            RootView()
                .environment(\.appTheme, .standard)
                // T18 — fires for both the `gshallelujah://` custom scheme and
                // the `applinks:` universal-link domains, on cold launch and
                // while running alike; see DeepLinkService's doc comment for
                // why that collapses Dart's separate capture/init/listen
                // trio into this one modifier.
                //
                // T23 — Google Sign-In's browser-redirect callback also
                // arrives through this same modifier (its own registered
                // scheme, see Info.plist), so `GIDSignIn` gets first look;
                // `handle(url)` returns `true` only for a URL it recognizes
                // as its own callback, matching the standard GoogleSignIn-iOS
                // integration pattern.
                // Siri voice play — hand-off from `SiriIntentsExtension`.
                .onContinueUserActivity(SiriPlayService.activityType) { activity in
                    guard let query = SiriPlayService.query(from: activity) else { return }
                    Task { @MainActor in await SiriPlayService().play(query: query) }
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    DeepLinkService.shared.receive(url)
                }
        }
    }
}
