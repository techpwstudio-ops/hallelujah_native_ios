import Foundation

/// Ports `NotificationPrefsService`'s (`lib/services/notification_prefs_service.dart`)
/// OPT-OUT semantics, not opt-in: a topic is enabled unless explicitly
/// turned off. FCM topic subscriptions live on Google's servers and a topic
/// the admin creates next month must still reach handsets that were
/// installed today — with an opt-in default every new channel would ship
/// dead. `bibleNotificationsEnabled` is a single separate switch gating
/// verse-of-day/Daily Bible pushes as one, fanned out per Bible language
/// server-side — not this store's concern.
///
/// An actor, not a `@MainActor @Observable` view-facing store, mirroring
/// `CurrentUserStore`'s shape (`App/Core/Security/CurrentUserStore.swift`)
/// and `HomeFeedCache`'s (`App/Core/Persistence/HomeFeedCache.swift`): both
/// are `KeyValueStoring`-backed actors loaded once at construction, safe to
/// call from any context — this feeds the push-registration path
/// (`PushNotificationTokenRegistrar`), which runs off the main actor.
actor NotificationPreferencesStore {
    private let keyValueStore: any KeyValueStoring

    private var optOut: [String: Bool]
    private(set) var bibleNotificationsEnabled: Bool

    private static let topicOptOutKey = "notificationTopicOptOut"
    private static let bibleEnabledKey = "notificationBibleEnabled"

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
        if let data = keyValueStore.data(forKey: Self.topicOptOutKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            optOut = decoded
        } else {
            optOut = [:]
        }
        // `KeyValueStoring.bool(forKey:)` can't distinguish "never set" from
        // "explicitly false" (`UserDefaults.bool(forKey:)` returns `false`
        // for an absent key either way) — indistinguishable from an opt-OUT
        // default here, the opposite of what this flag needs. Read through
        // `string(forKey:)` instead, whose `nil` unambiguously means "never
        // set" -> default enabled, matching Dart's `getBoolean() ?? true`.
        bibleNotificationsEnabled = keyValueStore.string(forKey: Self.bibleEnabledKey) != "false"
    }

    /// True unless the user explicitly turned this topic off.
    func isTopicEnabled(_ topicKey: String) -> Bool {
        optOut[topicKey] != true
    }

    func setTopicEnabled(_ topicKey: String, _ enabled: Bool) {
        if enabled {
            optOut.removeValue(forKey: topicKey)
        } else {
            optOut[topicKey] = true
        }
        if let data = try? JSONEncoder().encode(optOut) {
            keyValueStore.setData(data, forKey: Self.topicOptOutKey)
        }
    }

    func setBibleNotificationsEnabled(_ enabled: Bool) {
        bibleNotificationsEnabled = enabled
        keyValueStore.setString(enabled ? "true" : "false", forKey: Self.bibleEnabledKey)
    }

    /// The COMPLETE current subscribed set, for
    /// `PushNotificationTokenRegistrar.syncTopics(topicKeys:)` — the server
    /// replaces rather than merges, so this (not an incremental diff) is what
    /// every sync call must send.
    func enabledTopicKeys(among topics: [NotificationTopic]) -> [String] {
        topics.map(\.topicKey).filter { isTopicEnabled($0) }
    }
}
