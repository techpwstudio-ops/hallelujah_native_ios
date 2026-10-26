import Foundation

/// The infrastructure-level part of `OurSession.logout()`
/// (`lib/utils/session.dart`) that the session actor itself can trigger no
/// matter why the session ended (explicit sign-out, refresh-token expiry, a
/// refused refresh):
///
/// - `DataService.logout()` — forget the loaded `/dashboard/init` payload so
///   the next account fetches its own;
/// - `clearHomeV2FeedCache()` — wipe the cached home layouts, so the sign-in
///   screen's dashboard never shows the previous account's feed.
///
/// Feature-specific teardown (downloads, saved library, realtime socket,
/// current user, membership) stays in `AppComposition`'s `onLogout` closure,
/// next to the objects it needs.
enum SessionTeardown {
    static func perform(container: DependencyContainer = .current) {
        Task { @MainActor in AppDataSync.shared.reset() }
        // Private proxy images (Emet attachments) must not outlive the account.
        Task.detached(priority: .utility) { ArtworkDiskCache.removeAll() }
        if let homeCache = container.resolveIfRegistered(HomeFeedCache.self) {
            Task {
                for type in [HomeContentType.all, .music, .episode] {
                    await homeCache.clear(type: type)
                }
            }
        }
    }
}
