import Foundation
import Observation

/// Native port of `DataService.getInitData()` (`lib/services/data_service.dart`)
/// — the signed-in app's bootstrap fetch of `/dashboard/init`:
///
/// - `settings` -> `RemoteSettings` (`showSubscription`, `adsEnabled`,
///   `cdnUrl`), persisted for the next launch (`SettingsService.set`);
/// - `topics` / `bookLanguages` / `languages` -> `InitDataSnapshot`, which the
///   FCM topic sync reads (`FCMTopicManager`);
/// - `invite` -> the family-plan invite sheet;
/// - a cached user with a `deletingDate` -> the "Deletion Scheduled" sheet
///   (shown after every non-silent sync, successful or not).
///
/// Features that only need one slice (genres, topics for the settings page)
/// keep fetching their own; this is the app-wide copy.
///
/// Retry parity: a payload that has never landed is chased on a backoff while
/// the device looks online and at once when connectivity returns
/// (`ReconnectRetry`), because it carries the remote settings and a cold start
/// with no signal otherwise ran on defaults — premium button hidden — until
/// the next launch. The fetch in progress is shared, so two triggers landing
/// together make one request.
@MainActor
@Observable
final class AppDataSync {
    static let shared = AppDataSync()

    /// Bumped after every non-silent sync finishes (success or failure) and
    /// after every successful silent one — `AppInfrastructureHost` reacts to
    /// it by presenting the invite / pending-deletion sheets, the equivalent
    /// of the `showInviteReceivedSheet` / `showAccountDeletionSheet` calls at
    /// the end of `_fetchInitData`.
    private(set) var syncGeneration = 0
    /// The invite from the latest payload, consumed by the host.
    private(set) var pendingInvite: InitInviteInfo?
    private(set) var isInitialised = false
    private(set) var snapshot: InitDataSnapshot

    private let keyValueStore: any KeyValueStoring
    private let logger = AppLogger(category: .networking)
    private var inFlight: Task<Bool, Never>?
    private var retry: ReconnectRetry?
    private var syncedUserID: String?

    private static let snapshotKey = "initDataSnapshot"

    init(keyValueStore: any KeyValueStoring = UserDefaultsKeyValueStore()) {
        self.keyValueStore = keyValueStore
        if let data = keyValueStore.data(forKey: Self.snapshotKey),
           let stored = try? JSONDecoder().decode(InitDataSnapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = InitDataSnapshot()
        }
    }

    /// `getInitData({force, silent})`. Returns whether a payload landed.
    @discardableResult
    func sync(force: Bool = false, silent: Bool = false) async -> Bool {
        let succeeded = await load(force: force, silent: silent)
        // Only chase a payload that has never landed. A failed forced refresh
        // keeps the data already loaded, so there is nothing to retry for.
        if succeeded || isInitialised {
            retry?.cancel()
        } else {
            makeRetryIfNeeded().arm()
        }
        if succeeded || !silent {
            syncGeneration += 1
        }
        return succeeded
    }

    /// Called when the shell mounts: a different signed-in account than the
    /// one the payload was fetched for starts over (`DataService.logout()`).
    func prepare(forUserID userID: String?) {
        if syncedUserID != userID { reset() }
        syncedUserID = userID
    }

    /// `DataService.logout()`: forget "loaded" so the next account fetches its
    /// own payload, and stop chasing the old one.
    func reset() {
        isInitialised = false
        pendingInvite = nil
        retry?.cancel()
    }

    /// Hands the invite to the host exactly once.
    func takePendingInvite() -> InitInviteInfo? {
        defer { pendingInvite = nil }
        return pendingInvite
    }

    // MARK: - Fetch

    private func makeRetryIfNeeded() -> ReconnectRetry {
        if let retry { return retry }
        let created = ReconnectRetry(
            attempt: { [weak self] in
                guard let self else { return true }
                return await self.syncForRetry()
            },
            onlineChanges: ReachabilityBroadcast.shared.changes(),
            isOnline: { ReachabilityBroadcast.shared.isOnline }
        )
        retry = created
        return created
    }

    /// The retry's attempt: silent, and it must not re-arm the retry itself
    /// (`ReconnectRetry.fire` does that from the returned result).
    private func syncForRetry() async -> Bool {
        let succeeded = await load(force: false, silent: true)
        if succeeded { syncGeneration += 1 }
        return succeeded
    }

    private func load(force: Bool, silent: Bool) async -> Bool {
        if isInitialised && !force { return true }
        if !force, let inFlight { return await inFlight.value }
        let task = Task { await self.fetch(silent: silent) }
        inFlight = task
        let result = await task.value
        // A newer forced fetch may have replaced it; only clear our own.
        if inFlight == task { inFlight = nil }
        return result
    }

    private func fetch(silent: Bool) async -> Bool {
        let client: HTTPClient = DependencyContainer.current.resolve()
        do {
            let response = try await client.send(.dashboardInit, silent: silent)
            guard response.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any] else {
                logger.warning("dashboard/init returned \(response.statusCode)")
                return false
            }
            isInitialised = true

            if let settings = json["settings"] as? [String: Any] {
                RemoteSettings.apply(settings: settings)
            }

            let parsed = InitDataSnapshot(json: json)
            snapshot = InitDataSnapshot(
                topics: json["topics"] != nil ? parsed.topics : snapshot.topics,
                bookLanguages: json["bookLanguages"] != nil ? parsed.bookLanguages : snapshot.bookLanguages,
                languages: json["languages"] != nil ? parsed.languages : snapshot.languages
            )
            if let data = try? JSONEncoder().encode(snapshot) {
                keyValueStore.setData(data, forKey: Self.snapshotKey)
            }

            // Subscription follows the topics just stored — never the
            // display-name loop this replaced in Dart (see
            // `FCMTopicManager.syncLanguageScopedTopics`).
            await FCMTopicManager.shared.syncLanguageScopedTopics()

            if let invite = InitInviteInfo(json: json) {
                pendingInvite = invite
            }
            return true
        } catch {
            logger.warning("dashboard/init failed: \(error)")
            return false
        }
    }
}

extension InitDataSnapshot {
    init(topics: [Topic], bookLanguages: [String], languages: [String]) {
        self.init()
        self.topics = topics
        self.bookLanguages = bookLanguages
        self.languages = languages
    }
}
