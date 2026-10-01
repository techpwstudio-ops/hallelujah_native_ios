import Foundation

/// T66 — the server-defined push-notification topics this user may
/// subscribe to. Mirrors `FirebaseMessagingService.eligibleTopics()`
/// (`fcm_service.dart`): the settings screen's source of what to offer a
/// switch for, and the set `PushNotificationTokenRegistrar.syncTopics`
/// reports from (via `NotificationPreferencesStore.enabledTopicKeys(among:)`).
protocol NotificationTopicsRepository: Sendable {
    /// Global topics (`language == nil`) plus the ones whose `language`
    /// matches `reachLanguage`, compared case-insensitively — the same
    /// filter `syncLanguageScopedTopics`/`eligibleTopics()` apply
    /// (`fcm_service.dart`), so a caller can never be offered or subscribed
    /// to a topic that would be unsubscribed again on the next sync.
    ///
    /// `reachLanguage` mirrors `FirebaseMessagingService._reachLanguage()`:
    /// the caller resolves it once, from the signed-in `User`'s
    /// `primaryLanguage` (else the first of `languages`, else "english"),
    /// and passes it in — this repository does not read `CurrentUserStore`
    /// itself.
    func fetchEligibleTopics(reachLanguage: String) async throws -> [NotificationTopic]
}
