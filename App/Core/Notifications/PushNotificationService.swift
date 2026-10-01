import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Native port of the `UNUserNotificationCenter`/`Messaging`-facing slice of
/// `FirebaseMessagingService` (`lib/services/fcm_service.dart`): authorization,
/// APNs/FCM token handoff, and foreground presentation. Tap-to-route is
/// `PushNotificationRouter`'s job, not this type's — `handleNotificationResponse`
/// below only extracts the payload and delegates.
///
/// `static let shared`, not `@Injected`, for the same reason `DeepLinkService`
/// documents for its own: `UNUserNotificationCenter.current().delegate` (a
/// deferred `AppDelegate` patch) has to be set before
/// `application(_:didFinishLaunchingWithOptions:)` returns for a cold-start
/// notification tap to be delivered reliably, well before this type's own
/// first access is guaranteed to happen — see `DeepLinkService`'s doc comment
/// for the full argument, which applies identically here.
///
/// Scope cut, deliberate: Dart's `NotificationService.showForegroundNotificationWithData`
/// exists only because Flutter has no native foreground-presentation hook —
/// `flutter_local_notifications` re-synthesizes a banner by hand for every
/// foreground push. `UNUserNotificationCenterDelegate.userNotificationCenter
/// (_:willPresent:withCompletionHandler:)` (a deferred `AppDelegate` patch,
/// calling `presentationOptions(for:)` below) is the correct native
/// replacement: returning presentation options lets the system show the real
/// APNs/FCM banner itself, so nothing here re-posts a local notification.
@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    @Injected private var httpClient: HTTPClient
    private let logger = AppLogger(category: .notifications)

    /// Set once `activate()` has run — the gate `didReceiveFCMToken` checks
    /// before flushing immediately, mirroring `DeepLinkService.coordinator`
    /// being the gate `receive(_:)` checks before buffering into `pendingURL`.
    private var isActivated = false
    private var cachedFCMToken: String?

    private init() {}

    /// Called from `AppShellView.onAppear` — the same lifecycle point
    /// `DeepLinkService.attach(coordinator:)` already uses, matching Dart's
    /// own post-sign-in FCM `init()` call site (`session.dart`), not
    /// `main.dart`: the shell only ever mounts for a signed-in session, and
    /// `saveFcmToken` (`flushCachedTokenIfNeeded` below) needs a valid access
    /// token to succeed.
    func activate() {
        isActivated = true
        Task {
            _ = await requestAuthorizationIfNeeded()
            UIApplication.shared.registerForRemoteNotifications()
            await flushCachedTokenIfNeeded()
        }
    }

    /// Mirrors `DeepLinkService.detach()`. Nothing currently tears the shell
    /// down mid-session (sign-out isn't wired until T20-24 lands sign-out),
    /// but this costs nothing now and is correct the day something does.
    func deactivate() {
        isActivated = false
    }

    /// `messaging.requestPermission(...)` (`fcm_service.dart`'s `init()`),
    /// minus `criticalAlert`/`announcement`/`carPlay`: `criticalAlert`
    /// specifically requires an Apple-granted entitlement this project has
    /// no evidence of holding, and requesting an unentitled option is a
    /// silent no-op at best — dropped deliberately here, unlike Dart's
    /// speculative request for all of them.
    func requestAuthorizationIfNeeded() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            logger.warning("requestAuthorization failed: \(error)")
            return false
        }
    }

    /// `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// (a deferred patch) hands the raw APNs token off here; `Messaging`
    /// derives the FCM token from it and reports it back via
    /// `didReceiveFCMToken` (`MessagingDelegate`, also deferred).
    func didReceiveAPNsToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        logger.warning("APNs registration failed: \(error)")
    }

    /// `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` (a
    /// deferred `AppDelegate` patch) hands the FCM token off here. Can fire
    /// before `activate()` has ever run — `Messaging`'s delegate callback
    /// isn't gated on authorization or sign-in — so a token that arrives
    /// early is cached rather than sent immediately (a `saveFcmToken` call
    /// made before sign-in would 401 anyway); `activate()` flushes it once
    /// the shell is up. A token that arrives once already activated (e.g. a
    /// mid-session `onTokenRefresh`) flushes right away.
    func didReceiveFCMToken(_ token: String?) {
        cachedFCMToken = token
        guard isActivated else { return }
        Task { await flushCachedTokenIfNeeded() }
    }

    /// `willPresent`'s return value (a deferred `AppDelegate` patch) — see
    /// this type's doc comment for why this replaces Dart's manual
    /// local-notification synthesis outright, rather than porting it.
    func presentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    /// `didReceive response:` (a deferred `AppDelegate`/scene-delegate
    /// patch) hands the tap off here.
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        PushNotificationRouter.shared.handle(userInfo: userInfo)
    }

    /// `saveUserFcmToken`'s real call site (`fcm_service.dart`'s `init()`,
    /// fed by `getToken()`/`onTokenRefresh`) — `PushNotificationTokenRegistrar`
    /// (a sibling T66 file) owns the actual request; this only owns WHEN to
    /// fire it. Unlike `PlaybackAnalyticsDeviceInfo.deviceID` (server-assigned
    /// at auth, no native flow persists one yet — `nil` is correct there),
    /// the backend's `saveUserFcmToken` 400s outright without a `deviceId`
    /// (`user.controller.js:301`) and no `device-id`/`x-device-id` request
    /// header exists yet to fall back to (`HTTPClient.swift`'s own T15 TODO)
    /// — so this must be a real, client-generated identifier, not `nil`.
    /// `identifierForVendor` is the standard native id for exactly this case.
    private func flushCachedTokenIfNeeded() async {
        guard let token = cachedFCMToken else { return }
        cachedFCMToken = nil
        let deviceID = UIDevice.current.identifierForVendor?.uuidString
        await PushNotificationTokenRegistrar(client: httpClient).registerToken(token, deviceID: deviceID)
    }
}
