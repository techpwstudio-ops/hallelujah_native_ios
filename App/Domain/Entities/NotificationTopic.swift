import Foundation

/// Ports `NotificationTopicModel` (`lib/models/notifications_topics.dart`) —
/// a server-defined push-notification topic. Dart's `title` (a Realm-only
/// field nothing reads outside the offline topic cache) and its Realm
/// `@PrimaryKey` plumbing aren't carried over: this rewrite fetches topics
/// live off `/dashboard/init` rather than mirroring them into a local table.
struct NotificationTopic: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let topicKey: String

    /// Which language audience this topic addresses, as the server's
    /// canonical name (e.g. "Telugu"). `nil` means the topic is NOT
    /// language-scoped — a global announcement everyone is eligible for. See
    /// `NotificationTopicsRepository.fetchEligibleTopics(reachLanguage:)` for
    /// the comparison this drives.
    let language: String?
}
