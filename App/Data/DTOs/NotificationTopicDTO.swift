import Foundation

// MARK: - Dashboard init slice

/// `getUserAppInitData` (`dashboard.controller.js`) → `/dashboard/init`'s
/// `topics` key: `prisma.pushNotificationTopic.findMany({ where: {
/// isActive: true, targetType: { in: ["user", "both"] } } })`, selected down
/// to `id`/`name`/`topicKey`/`language`/`targetType`. Every language is
/// included on purpose — the controller's own comment on
/// `handlesTopicLanguages` explains why an unfiltered list has to reach a
/// current build — so `RemoteNotificationTopicsRepository` narrows this to
/// the caller's `reachLanguage` itself, mirroring
/// `FirebaseMessagingService.eligibleTopics()` (`fcm_service.dart`). Decodes
/// just this one key out of the same broader init payload
/// `DashboardInitGenresDTO` (`ContentDTOs.swift`) decodes its own slice of.
struct DashboardInitTopicsDTO: Decodable, Sendable {
    let topics: [NotificationTopicDTO]
}

/// `targetType` isn't carried over — the query above has already applied
/// that filter, and `NotificationTopic` has nothing that would use it.
struct NotificationTopicDTO: Decodable, Sendable {
    let id: String
    let name: String
    let topicKey: String
    let language: String?
}

extension NotificationTopicDTO {
    func toDomain() -> NotificationTopic {
        NotificationTopic(id: id, name: name, topicKey: topicKey, language: language)
    }
}

// MARK: - Push token / topic sync requests

/// `saveUserFcmToken` (`user.controller.js`) → `POST /user/save/fcm-token`'s
/// body. Both fields are required server-side — a 400 if either is missing —
/// independent of `SyncNotificationTopicsRequest` below.
struct SaveFcmTokenRequest: Encodable, Sendable {
    let fcmToken: String
    let deviceId: String?
}

/// `syncNotificationTopics` (`notificationTopic.controller.js`) → `POST
/// /user/notification-topics/sync`'s body. `topicKeys` must be the device's
/// COMPLETE current subscription set — the server REPLACES what it holds for
/// this device rather than merging, so an unsubscribe is expressed by
/// leaving a key out; an empty array is valid and means "subscribed to
/// nothing". Mirrors `reportSubscriptions`'s request body (`fcm_service.dart`).
struct SyncNotificationTopicsRequest: Encodable, Sendable {
    let fcmToken: String
    let deviceId: String?
    let deviceType: String?
    let deviceName: String?
    let topicKeys: [String]
}
