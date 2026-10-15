import Foundation

/// Pure parsing of an incoming FCM data push — the non-Firebase half of
/// `FirebaseMessagingService.handleFcm` (`lib/services/fcm_service.dart`).
enum PushPayload {
    /// What `handleFcm` does with a push that is not a verse-of-day delivery.
    struct RealtimeEvent: Equatable {
        let name: String
        /// The whole payload as a JSON-safe dictionary, with `data` already
        /// decoded when the server sent it as a JSON string — what
        /// `RealtimeEventHandler.dispatch(event, map)` receives in Dart.
        let envelope: [String: Any]

        static func == (lhs: RealtimeEvent, rhs: RealtimeEvent) -> Bool {
            lhs.name == rhs.name && NSDictionary(dictionary: lhs.envelope).isEqual(to: rhs.envelope)
        }
    }

    /// `userInfo["topic"] == "verse_of_day"` pushes are delivery markers
    /// (`markVerseOfDayDelivered`), handled separately.
    static func verseOfDayID(from userInfo: [AnyHashable: Any]) -> String? {
        guard (userInfo["topic"] as? String) == "verse_of_day",
              let id = userInfo["verseOfDayId"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// The `else` branch of `handleFcm`:
    ///
    /// 1. `data` arrives as a JSON string over FCM; decode it when it parses.
    /// 2. A push addressed to a `user-<id>` room (`fcmToken` key) is dropped
    ///    unless it is for the signed-in account — a device that has seen more
    ///    than one account on the same install keeps the old `user-<id>`
    ///    subscription.
    /// 3. Only pushes with a non-empty string `event` are dispatched. An admin
    ///    push carries `type`/`notificationId`/`shareableType` and no `event`,
    ///    and must fall through to just showing the banner.
    static func realtimeEvent(from userInfo: [AnyHashable: Any], currentUserID: String?) -> RealtimeEvent? {
        var map: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            map[key] = value
        }

        if let raw = map["data"] as? String,
           let decoded = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed]) {
            map["data"] = decoded
        }

        if let target = map["fcmToken"], "\(target)".contains("user-"), "\(target)" != "user-\(currentUserID ?? "null")" {
            return nil
        }

        guard let event = map["event"] as? String, !event.isEmpty else { return nil }
        guard JSONSerialization.isValidJSONObject(map) else {
            // `aps` and `gcm.*` keys are already JSON-safe; anything else the
            // OS added is not part of the contract, so keep only what is.
            let safe = map.filter { JSONSerialization.isValidJSONObject([$0.key: $0.value]) }
            return RealtimeEvent(name: event, envelope: safe)
        }
        return RealtimeEvent(name: event, envelope: map)
    }

    /// `gcm.message_id` — the key used to de-duplicate a push iOS hands to
    /// both `willPresent` and `didReceiveRemoteNotification` (Flutter has one
    /// listener per state, so Dart never sees it twice).
    static func messageID(from userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["gcm.message_id"] as? String) ?? (userInfo["google.c.a.c_id"] as? String)
    }
}

/// Remembers the last few push ids so one push is processed once.
final class PushDeduplicator: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    private let capacity: Int

    init(capacity: Int = 50) {
        self.capacity = capacity
    }

    /// `true` the first time an id is seen; ids of `nil` are never treated as
    /// duplicates.
    func isFirstSighting(of id: String?) -> Bool {
        guard let id else { return true }
        lock.lock()
        defer { lock.unlock() }
        if seen.contains(id) { return false }
        seen.append(id)
        if seen.count > capacity { seen.removeFirst(seen.count - capacity) }
        return true
    }
}
