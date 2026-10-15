import Foundation

/// The pure decision half of `FirebaseMessagingService`'s topic management
/// (`lib/services/fcm_service.dart`) — which FCM topics a device should be on —
/// separated from the Firebase calls so it can be unit tested.
enum FCMTopicPlanner {
    struct Plan: Equatable, Sendable {
        var subscribe: [String]
        var unsubscribe: [String]
    }

    /// `parseLanguages`: comma separated, trimmed, lowercased. Dart does not
    /// drop empty entries (`"a,,b"` yields an empty string between); that
    /// would subscribe to the invalid topic `user-lang-` and fail, so empties
    /// are dropped here.
    static func parseLanguages(_ languages: String?) -> [String] {
        guard let languages else { return [] }
        return languages
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// `_reachLanguage()`: the language the user should be REACHED in. Mirrors
    /// `resolveReachLanguage()` on the server exactly — explicit choice, then
    /// the first selected language, then English — lowercased because the
    /// topic side is compared lowercased too. Any divergence is a push that is
    /// delivered to nobody.
    static func reachLanguage(primaryLanguage: String?, languages: String?) -> String {
        if let primary = primaryLanguage?.trimmingCharacters(in: .whitespaces), !primary.isEmpty {
            return primary.lowercased()
        }
        if let first = parseLanguages(languages).first { return first }
        return "english"
    }

    /// Whether `topic` is eligible for `reachLanguage`: no language (or an
    /// empty one) means a global announcement everyone gets; otherwise the
    /// case-insensitive language must match.
    static func isEligible(topicLanguage: String?, reachLanguage: String) -> Bool {
        let language = topicLanguage?.trimmingCharacters(in: .whitespaces).lowercased()
        return language == nil || language!.isEmpty || language == reachLanguage
    }

    /// `syncLanguageScopedTopics`: subscribe to the topics that are both
    /// eligible and not switched off by the user, unsubscribe from the rest.
    /// Subscribing alone would be a one-way ratchet — FCM subscriptions live on
    /// Google's servers, so a user who switches from Telugu to Hindi would stay
    /// on the Telugu topic forever.
    static func languageScopedPlan(
        topics: [(key: String?, language: String?)],
        reachLanguage: String,
        isTopicEnabled: (String) -> Bool
    ) -> Plan {
        var plan = Plan(subscribe: [], unsubscribe: [])
        for topic in topics {
            guard let key = topic.key, !key.isEmpty else { continue }
            let wanted = isEligible(topicLanguage: topic.language, reachLanguage: reachLanguage) && isTopicEnabled(key)
            if wanted {
                plan.subscribe.append(key)
            } else {
                plan.unsubscribe.append(key)
            }
        }
        return plan
    }

    /// `subscribeVerseOfDay`. `bookLanguages` are the Bible language names
    /// (`BookLangModel`); the per-language topic is the base topic with the
    /// lowercased language appended with no separator (`verse_of_dayenglish`),
    /// exactly as the server names it. In development the base topic is
    /// `verse_of_day_dev` and the production ones are unsubscribed first.
    static func verseOfDayPlan(
        isDevelopment: Bool,
        bibleLanguage: String?,
        bookLanguages: [String],
        notificationsEnabled: Bool
    ) -> Plan {
        let language = (bibleLanguage ?? "english").lowercased()
        var topic = "verse_of_day"
        var unsubscribe: [String] = []

        if isDevelopment {
            for bookLanguage in bookLanguages {
                unsubscribe.append("\(topic)\(bookLanguage.lowercased())")
            }
            unsubscribe.append(topic)
            topic = "verse_of_day_dev"
        }
        // Always drop the stale per-language rooms, even for an opted-out
        // user — skipping this would strand someone who changed Bible
        // language while opted out.
        for bookLanguage in bookLanguages {
            unsubscribe.append("\(topic)\(bookLanguage.lowercased())")
        }

        guard notificationsEnabled else {
            unsubscribe.append(topic)
            unsubscribe.append("\(topic)\(language)")
            return Plan(subscribe: [], unsubscribe: unsubscribe)
        }
        return Plan(subscribe: [topic, "\(topic)\(language)"], unsubscribe: unsubscribe)
    }

    /// `setUserSpecificTopics`: `users` (`users_dev` in development) and the
    /// per-account `user-<id>`. Dart would subscribe to the literal
    /// `user-null` with no signed-in user; that room is skipped here.
    static func userTopics(userID: String?, isDevelopment: Bool) -> [String] {
        var topics = ["users\(isDevelopment ? "_dev" : "")"]
        if let userID, !userID.isEmpty { topics.append("user-\(userID)") }
        return topics
    }

    /// `subscribeContentLanguage`: leave every `user-lang-*` room, then join
    /// the ones the user selected.
    static func contentLanguagePlan(allLanguages: [String], selected: [String]) -> Plan {
        Plan(
            subscribe: selected.map { "user-lang-\($0.lowercased())" },
            unsubscribe: allLanguages.map { "user-lang-\($0.lowercased())" }
        )
    }

    /// Firebase rejects topic names outside `[a-zA-Z0-9-_.~%]+`.
    static func isValidTopicName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || "-_.~%".unicodeScalars.contains($0)
        }
    }
}
