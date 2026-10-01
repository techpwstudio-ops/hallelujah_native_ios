import Foundation

/// Ports the two server-reporting calls `FirebaseMessagingService` makes
/// once it has an FCM token (`fcm_service.dart`): the standalone token save
/// (`OurSession.updateFcmToken`'s server half) and `reportSubscriptions`.
/// Both are fire-and-forget by design — `reportSubscriptions`'s own doc
/// comment: "a failed report costs a stale count [[on the admin dashboard]]
/// and must never surface to the user or block a subscription that already
/// succeeded on Firebase's side." Neither method here throws for exactly
/// that reason: a caller that wants to react to failure has nothing to
/// catch.
final class PushNotificationTokenRegistrar: Sendable {
    private let client: HTTPClient
    private let logger = AppLogger(category: .networking)

    init(client: HTTPClient) {
        self.client = client
    }

    /// `saveUserFcmToken` — `Endpoint.saveFcmToken`. Simpler standalone token
    /// save, independent of `syncTopics` below.
    func registerToken(_ fcmToken: String, deviceID: String?) async {
        do {
            let body = try JSONEncoder().encode(SaveFcmTokenRequest(fcmToken: fcmToken, deviceId: deviceID))
            let response = try await client.send(.saveFcmToken, body: body)
            if response.statusCode != 200 {
                logger.warning("saveFcmToken returned \(response.statusCode)")
            }
        } catch {
            logger.warning("saveFcmToken failed: \(error)")
        }
    }

    /// `reportSubscriptions` — `Endpoint.syncNotificationTopics`. `topicKeys`
    /// must be the device's COMPLETE current subscription set; see
    /// `SyncNotificationTopicsRequest`'s doc comment.
    func syncTopics(
        fcmToken: String,
        deviceID: String?,
        deviceType: String,
        deviceName: String?,
        topicKeys: [String]
    ) async {
        do {
            let request = SyncNotificationTopicsRequest(
                fcmToken: fcmToken,
                deviceId: deviceID,
                deviceType: deviceType,
                deviceName: deviceName,
                topicKeys: topicKeys
            )
            let body = try JSONEncoder().encode(request)
            let response = try await client.send(.syncNotificationTopics, body: body)
            if response.statusCode != 200 {
                logger.warning("syncNotificationTopics returned \(response.statusCode)")
            }
        } catch {
            logger.warning("syncNotificationTopics failed: \(error)")
        }
    }
}
