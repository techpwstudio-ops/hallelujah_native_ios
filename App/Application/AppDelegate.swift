import FirebaseMessaging
import UIKit

/// T46 — the one hook `SwiftUI.App` has no direct equivalent for:
/// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
/// fires when iOS relaunches the app in the background to hand back events
/// (progress/completion) a `DownloadEngine` background `URLSession` produced
/// while suspended. `GHallelujahApp` installs this via
/// `@UIApplicationDelegateAdaptor` solely to receive that one callback and
/// forward it to the single registered `DownloadEngine` — everything else
/// about app lifecycle stays on the SwiftUI `App`/`Scene` path, unchanged.
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate, @preconcurrency MessagingDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let engine: DownloadEngine = DependencyContainer.current.resolve()
        engine.handleEventsForBackgroundURLSession(identifier: identifier, completionHandler: completionHandler)
    }

    // T66 — must be set before `didFinishLaunchingWithOptions` returns for
    // cold-start notification taps to be reliably captured.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationService.shared.didReceiveAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationService.shared.didFailToRegisterForRemoteNotifications(error)
    }

    /// Silent / background pushes (`UIBackgroundModes: remote-notification`) —
    /// `FirebaseMessaging.onBackgroundMessage` -> `handleBackground`
    /// (`main.dart`, `fcm_service.dart`).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        _ = Messaging.messaging().appDidReceiveMessage(userInfo)
        PushNotificationService.shared.handleRemoteNotification(userInfo: userInfo)
        completionHandler(.newData)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        PushNotificationService.shared.didReceiveFCMToken(fcmToken)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(PushNotificationService.shared.presentationOptions(for: notification))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        PushNotificationService.shared.handleNotificationResponse(response)
        completionHandler()
    }
}
