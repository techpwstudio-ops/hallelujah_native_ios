import Foundation

/// The slices of a `/dashboard/init` response (`getUserAppInitData`) that
/// native code outside a single feature reads: Dart mirrors them into Realm
/// (`DataService._updateNotificationTopics`, `updateBookLanguages`,
/// `updateLanguages`), and `FirebaseMessagingService` reads those tables back
/// when it syncs push topics. Persisted as one small JSON blob so a launch
/// with no signal still knows the last topic / language lists.
struct InitDataSnapshot: Codable, Sendable, Equatable {
    /// `getNotificationTopicModel`. Every language's topics are kept, not just
    /// the user's — unsubscribing from the non-matching ones is half of
    /// `syncLanguageScopedTopics`.
    struct Topic: Codable, Sendable, Equatable {
        var id: String
        var name: String?
        var topicKey: String?
        var language: String?
    }

    var topics: [Topic] = []
    /// `bookLanguages[].language` — the Bible languages
    /// (`BookLangModel.language`).
    var bookLanguages: [String] = []
    /// `languages[].name` — the content languages (`languageProvider.allLanguages`).
    var languages: [String] = []

    init() {}

    /// Parses the already-decoded response object. Keys that are absent leave
    /// the matching list empty; malformed rows are skipped rather than
    /// failing the whole payload.
    init(json: [String: Any]) {
        if let rows = json["topics"] as? [[String: Any]] {
            topics = rows.compactMap { row in
                guard let id = Self.string(row["id"]) else { return nil }
                return Topic(
                    id: id,
                    name: row["name"] as? String,
                    topicKey: row["topicKey"] as? String,
                    language: row["language"] as? String
                )
            }
        }
        if let rows = json["bookLanguages"] as? [[String: Any]] {
            bookLanguages = rows.compactMap { $0["language"] as? String }
        }
        if let rows = json["languages"] as? [[String: Any]] {
            languages = rows.compactMap { $0["name"] as? String }
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Int { return String(value) }
        return nil
    }
}

/// `map['invite']` of the init payload → `showInviteReceivedSheet(inviteId:
/// inviterName:planName:)`.
struct InitInviteInfo: Sendable, Equatable {
    let inviteId: String
    let inviterName: String?
    let planName: String?

    init(inviteId: String, inviterName: String?, planName: String?) {
        self.inviteId = inviteId
        self.inviterName = inviterName
        self.planName = planName
    }

    /// `map['invite']['id']`, `['inviter']['name']`, `['subscription']
    /// ['planName']`. `nil` when there is no invite or it has no id.
    init?(json: [String: Any]) {
        guard let invite = json["invite"] as? [String: Any],
              let id = invite["id"] as? String, !id.isEmpty else { return nil }
        inviteId = id
        inviterName = (invite["inviter"] as? [String: Any])?["name"] as? String
        planName = (invite["subscription"] as? [String: Any])?["planName"] as? String
    }

    /// The realtime `premium.member.invite` shape — `data: {inviteId,
    /// inviterName, planName}` (`_onPremiumInviteReceived`).
    init?(realtimeData data: [String: Any]) {
        guard let id = data["inviteId"] as? String, !id.isEmpty else { return nil }
        inviteId = id
        inviterName = data["inviterName"] as? String
        planName = data["planName"] as? String
    }
}
