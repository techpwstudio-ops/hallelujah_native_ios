import FirebaseMessaging
import Foundation

/// Native port of the topic-subscription half of `FirebaseMessagingService`
/// (`lib/services/fcm_service.dart`): `init()`, `setUserSpecificTopics`,
/// `subscribeVerseOfDay`, `subscribeContentLanguage`,
/// `syncLanguageScopedTopics`, `reportSubscriptions`, `setTopicSubscription`.
/// Which topics to join is decided by `FCMTopicPlanner` (pure, tested); this
/// type only talks to Firebase and the backend.
///
/// FCM subscriptions live on Google's servers, not in the app, so nothing
/// server-side can move a device between topics — the device has to keep its
/// own subscriptions correct after a language or preference change, and
/// report the resulting set (`reportSubscriptions`) for the admin dashboard's
/// audience figures.
///
/// Nothing here runs until `activate()` has been called once (from
/// `PushNotificationService.activate()`, i.e. the signed-in shell), which also
/// keeps preference changes in unit tests from ever reaching Firebase.
@MainActor
final class FCMTopicManager {
    static let shared = FCMTopicManager()

    private let logger = AppLogger(category: .notifications)
    private var isInitialised = false

    private init() {}

    private var isDevelopment: Bool { AppConfiguration.current.environment != .production }
    private var container: DependencyContainer { .current }

    // MARK: - Lifecycle

    /// `FirebaseMessagingService.init()` the first time; on later calls (a new
    /// sign-in within the same process) only the account-specific topics are
    /// re-applied, as `createSession` does via `setUserSpecificTopics()`.
    func activate() async {
        if isInitialised {
            await setUserSpecificTopics()
            return
        }
        isInitialised = true

        await setUserSpecificTopics()
        await subscribeVerseOfDay()
        await subscribe(to: "song_updates")
        await syncLanguageScopedTopics()
        if isDevelopment {
            await subscribe(to: "debug")
        }
        await subscribeContentLanguage()
    }

    // MARK: - Topic groups

    /// `setUserSpecificTopics`.
    func setUserSpecificTopics() async {
        let user = await currentUser()
        for topic in FCMTopicPlanner.userTopics(userID: user?.id, isDevelopment: isDevelopment) {
            await subscribe(to: topic)
        }
    }

    /// `subscribeVerseOfDay`. Also what a Bible-language change re-runs
    /// (`changeReadLanguage`) and what the Daily Bible switch applies
    /// (`setBibleNotifications`).
    func subscribeVerseOfDay() async {
        let user = await currentUser()
        let enabled = await preferences()?.bibleNotificationsEnabled ?? true
        let plan = FCMTopicPlanner.verseOfDayPlan(
            isDevelopment: isDevelopment,
            bibleLanguage: user?.bibleLanguage,
            bookLanguages: AppDataSync.shared.snapshot.bookLanguages,
            notificationsEnabled: enabled
        )
        await apply(plan)
    }

    /// `subscribeContentLanguage`.
    func subscribeContentLanguage() async {
        let user = await currentUser()
        let plan = FCMTopicPlanner.contentLanguagePlan(
            allLanguages: AppDataSync.shared.snapshot.languages,
            selected: FCMTopicPlanner.parseLanguages(user?.languages)
        )
        await apply(plan)
    }

    /// `syncLanguageScopedTopics`: join the server-defined topics for this
    /// user's reach language that they have not switched off, leave every
    /// other one, then tell the server the resulting set.
    func syncLanguageScopedTopics() async {
        guard isInitialised else { return }
        let user = await currentUser()
        let reach = FCMTopicPlanner.reachLanguage(primaryLanguage: user?.primaryLanguage, languages: user?.languages)
        let topics = AppDataSync.shared.snapshot.topics

        var enabled: [String: Bool] = [:]
        if let preferences = preferences() {
            for topic in topics {
                if let key = topic.topicKey { enabled[key] = await preferences.isTopicEnabled(key) }
            }
        }
        let plan = FCMTopicPlanner.languageScopedPlan(
            topics: topics.map { (key: $0.topicKey, language: $0.language) },
            reachLanguage: reach,
            isTopicEnabled: { enabled[$0] ?? true }
        )
        await apply(plan)
        logger.info("language-scoped topics synced for \"\(reach)\"")
        await reportSubscriptions(plan.subscribe)
    }

    // MARK: - Change notifications

    /// A topic or Bible switch changed in `NotificationPreferencesStore`.
    /// The preference is already persisted (it is written FIRST, so the
    /// user's intent survives an FCM failure); this applies it.
    func preferencesDidChange() {
        guard isInitialised else { return }
        Task {
            await subscribeVerseOfDay()
            await syncLanguageScopedTopics()
        }
    }

    /// `changeContentLanguages`: the primary language decides which push
    /// topics this device belongs on, so changing it re-runs the topic sync.
    func contentLanguagesDidChange() {
        guard isInitialised else { return }
        Task {
            await subscribeContentLanguage()
            await subscribeVerseOfDay()
            await syncLanguageScopedTopics()
        }
    }

    /// `changeReadLanguage`.
    func bibleLanguageDidChange() {
        guard isInitialised else { return }
        Task { await subscribeVerseOfDay() }
    }

    // MARK: - Server report

    /// `reportSubscriptions`: always the COMPLETE set (the server replaces,
    /// it does not merge). Fire-and-forget — a failed report costs a stale
    /// count on a dashboard and must never surface to the user.
    func reportSubscriptions(_ topicKeys: [String]) async {
        let token = PushNotificationService.shared.latestFCMToken ?? Messaging.messaging().fcmToken
        guard let token, !token.isEmpty else { return }
        guard await currentUser()?.id != nil else { return }

        let model = DeviceHeaderInfo.current.model
        // `[brand, model].where(nonEmpty).join(' ')`.
        let deviceName = ["Apple", model].filter { !$0.isEmpty }.joined(separator: " ")
        let registrar: PushNotificationTokenRegistrar = container.resolve()
        await registrar.syncTopics(
            fcmToken: token,
            deviceID: DeviceIdentityStore.shared.deviceID,
            deviceType: "ios",
            deviceName: deviceName,
            topicKeys: topicKeys
        )
    }

    // MARK: - Firebase

    private func apply(_ plan: FCMTopicPlanner.Plan) async {
        // Leaving first, joining last: a topic present in both (the
        // dev-branch `verse_of_day_dev` case) ends up subscribed.
        for topic in plan.unsubscribe where !plan.subscribe.contains(topic) {
            await unsubscribe(from: topic)
        }
        for topic in plan.subscribe {
            await subscribe(to: topic)
        }
    }

    private func subscribe(to topic: String) async {
        guard FCMTopicPlanner.isValidTopicName(topic) else { return }
        do {
            try await Messaging.messaging().subscribe(toTopic: topic)
        } catch {
            logger.warning("subscribe(\(topic)) failed: \(error)")
        }
    }

    private func unsubscribe(from topic: String) async {
        guard FCMTopicPlanner.isValidTopicName(topic) else { return }
        do {
            try await Messaging.messaging().unsubscribe(fromTopic: topic)
        } catch {
            logger.warning("unsubscribe(\(topic)) failed: \(error)")
        }
    }

    // MARK: - Collaborators

    private func currentUser() async -> User? {
        guard let store = container.resolveIfRegistered(CurrentUserStore.self) else { return nil }
        return await store.user
    }

    private func preferences() -> NotificationPreferencesStore? {
        container.resolveIfRegistered(NotificationPreferencesStore.self)
    }
}
