import Foundation

/// What `OurSession.initializeApp()` (`lib/utils/session.dart`) kicks off once
/// the signed-in app is up, in the parts that have a native equivalent:
/// `OurSession.initSession()` (the access-token refresh timer) and
/// `DataService.init()` -> `getInitData()` (`AppDataSync`). Push topics and
/// the FCM token are `PushNotificationService.activate()`'s job, which calls
/// this.
///
/// Safe to call on every shell appearance: a re-appearing shell for the same
/// account is a cheap no-op (the init payload is only fetched until it has
/// landed once), while a different account signing in within the same process
/// resets the previous one's state first, as `DataService.logout()` does.
@MainActor
enum AppSessionBootstrap {
    static func shellDidAppear(container: DependencyContainer = .current) {
        if let session = container.resolveIfRegistered(Session.self) {
            Task { await session.startTokenMonitor() }
        }
        Task {
            let userID = await container.resolveIfRegistered(CurrentUserStore.self)?.user?.id
            AppDataSync.shared.prepare(forUserID: userID)
            await AppDataSync.shared.sync()
        }
        // `updateUserModel` runs this on every login/signup/refresh: cache the
        // user's Bible language for offline reading without being asked. It
        // no-ops when already saved, downloading or offline, so it is safe to
        // call on every appearance.
        if let bibleOffline = container.resolveIfRegistered(BibleOfflineDownloadService.self) {
            Task { await bibleOffline.ensureDefaultLanguageCached() }
        }
    }
}
