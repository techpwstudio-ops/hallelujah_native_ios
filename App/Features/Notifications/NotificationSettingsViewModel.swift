import Foundation
import UIKit

/// T66 — per-category notification preferences. Ports
/// `_NotificationSettingsPageState` (`lib/views/notification_settings_page.dart`):
/// one Bible-verse switch plus one switch per eligible `Updates` topic, each
/// independently busy-tracked the same way Dart's own `_busy`/`_run` pair
/// disables only the row whose own toggle is in flight.
///
/// `LoadState` mirrors `UserPlaylistDetailViewModel`'s own shape. `.empty`
/// is reachable only for the topics list (`fetchEligibleTopics` returning
/// `[]`) — the Bible section has no empty state of its own, same as Dart's
/// `CustomHeading(heading: 'Daily Bible')` section rendering unconditionally.
@Observable
@MainActor
final class NotificationSettingsViewModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded([NotificationTopic])
        case empty
        case failed
    }

    private(set) var state: LoadState = .loading
    private(set) var bibleNotificationsEnabled = false
    /// Per-topic-key on/off, keyed the same way `busyKeys` is — cached
    /// locally rather than re-read from the actor on every row render,
    /// since `Toggle`'s binding needs a synchronous value.
    private(set) var topicEnabled: [String: Bool] = [:]
    private(set) var busyKeys: Set<String> = []

    private let topicsRepository: any NotificationTopicsRepository
    private let preferencesStore: NotificationPreferencesStore
    private let tokenRegistrar: PushNotificationTokenRegistrar
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .content)
    private var loadTask: Task<Void, Never>?

    /// Dart's own literal `_busy.add('bible')` key (`_run`, ibid.) — kept as
    /// a sentinel in the same `Set` as topic keys rather than a second
    /// `Bool`/`Set` pair, so `isBusy(_:)` is one lookup for both the Bible
    /// switch and every topic row, matching `_switchTile`'s own single
    /// `busy` check.
    private static let bibleBusyKey = "bible"

    init(container: DependencyContainer = .current) {
        topicsRepository = container.resolve()
        preferencesStore = container.resolve()
        tokenRegistrar = container.resolve()
        currentUserStore = container.resolve()
    }

    func isBusy(_ topicKey: String) -> Bool { busyKeys.contains(topicKey) }
    var isBibleBusy: Bool { isBusy(Self.bibleBusyKey) }
    func isEnabled(_ topicKey: String) -> Bool { topicEnabled[topicKey] ?? false }

    func loadIfNeeded() async {
        guard case .loading = state, loadTask == nil else { return }
        await load()
    }

    func refresh() async {
        await load()
    }

    /// `FirebaseMessagingService.instance.setBibleNotifications(v)`. Not
    /// part of the topic-sync fire-and-forget below — the Bible verse isn't
    /// one of the `NotificationTopic`s `syncTopics(topicKeys:)` reports, so
    /// there is nothing new for that call to say after this toggle.
    func toggleBible(_ enabled: Bool) async {
        guard !isBibleBusy else { return }
        busyKeys.insert(Self.bibleBusyKey)
        defer { busyKeys.remove(Self.bibleBusyKey) }
        await preferencesStore.setBibleNotificationsEnabled(enabled)
        bibleNotificationsEnabled = enabled
    }

    /// `FirebaseMessagingService.instance.setTopicSubscription(key, v)`.
    /// The preference write lands first and unconditionally; the server
    /// sync after it is best-effort, matching Dart's own "preference is
    /// written FIRST, network call is best-effort" comment.
    func toggleTopic(_ topicKey: String, enabled: Bool) async {
        guard !isBusy(topicKey) else { return }
        busyKeys.insert(topicKey)
        defer { busyKeys.remove(topicKey) }
        await preferencesStore.setTopicEnabled(topicKey, enabled)
        topicEnabled[topicKey] = enabled
        syncTopicsFireAndForget()
    }

    private func load() async {
        state = .loading
        loadTask = Task {
            defer { loadTask = nil }
            bibleNotificationsEnabled = await preferencesStore.bibleNotificationsEnabled
            do {
                let language = await reachLanguage()
                let topics = try await topicsRepository.fetchEligibleTopics(reachLanguage: language)
                var enabled: [String: Bool] = [:]
                for topic in topics {
                    enabled[topic.topicKey] = await preferencesStore.isTopicEnabled(topic.topicKey)
                }
                topicEnabled = enabled
                state = topics.isEmpty ? .empty : .loaded(topics)
            } catch {
                logger.warning("fetch eligible notification topics failed: \(error)")
                state = .failed
            }
        }
        await loadTask?.value
    }

    /// `_reachLanguage()` (`fcm_service.dart`): the explicit choice, else
    /// the first parsed language, else English — lowercased, since the
    /// topic side (`NotificationTopicsRepository`) compares it lowercased
    /// too. Reads `CurrentUserStore` rather than a Settings-local cache, the
    /// same single source of truth `LanguageViewModel.initialize()` reads
    /// `languages`/`primaryLanguage` from.
    private func reachLanguage() async -> String {
        let user = await currentUserStore.user
        if let primary = user?.primaryLanguage?.trimmingCharacters(in: .whitespaces), !primary.isEmpty {
            return primary.lowercased()
        }
        let parsed = (user?.languages ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = parsed.first {
            return first.lowercased()
        }
        return "english"
    }

    /// Mirrors `setTopicSubscription`/`syncLanguageScopedTopics`
    /// (`fcm_service.dart`), which always report the user's COMPLETE
    /// enabled-topic-key set after any single change, not just the one that
    /// flipped — the server side replaces the subscription list wholesale
    /// rather than diffing it. Not awaited by the caller: the preference is
    /// already durably persisted by `NotificationPreferencesStore` before
    /// this runs, so nothing on screen depends on this call finishing.
    ///
    /// T66 scope note: there is no cached-FCM-token getter visible from this
    /// track yet — `PushNotificationService` (a sibling task's type) isn't
    /// in the tree at this file's write time. `cachedFCMToken()` always
    /// returns `nil` for now, which routes every toggle through the graceful
    /// skip below; once that getter exists, it is the one line to change.
    private func syncTopicsFireAndForget() {
        guard let fcmToken = cachedFCMToken() else {
            logger.debug("skipping notification-topic server sync: no FCM token available yet")
            return
        }
        let enabledTopicKeys = Array(topicEnabled.filter(\.value).keys)
        let device = UIDevice.current
        let deviceType = device.userInterfaceIdiom == .pad ? "tablet" : "mobile"
        let deviceName = device.name
        // No server-assigned device id is available natively yet — same gap
        // `PlaybackAnalyticsDeviceInfo.deviceID`'s own doc comment already
        // flags ("left nil rather than minting a local UUID the backend
        // never registered"). Moot today since this whole call is unreached
        // while `cachedFCMToken()` returns `nil`.
        let deviceID = ""
        let registrar = tokenRegistrar
        Task {
            await registrar.syncTopics(
                fcmToken: fcmToken,
                deviceID: deviceID,
                deviceType: deviceType,
                deviceName: deviceName,
                topicKeys: enabledTopicKeys
            )
        }
    }

    private func cachedFCMToken() -> String? { nil }
}
