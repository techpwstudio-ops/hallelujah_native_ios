import Foundation

/// A session only means something to the backend that issued it. Every
/// environment shares one bundle ID — and so one Keychain item — so running a
/// Staging build over a Production one (or pointing at localhost) would keep
/// the old tokens and send them to a server that has never seen them: every
/// call 403s and Home lands on "Failed to load home".
///
/// Remembers the `apiBaseURL` the stored session was created against and
/// reports when it no longer matches, so `AppComposition` can sign out.
struct SessionEnvironmentGuard {
    static let storageKey = "session.apiBaseURL"

    private let store: any KeyValueStoring
    private let current: String

    init(apiBaseURL: URL, store: any KeyValueStoring = UserDefaultsKeyValueStore()) {
        self.store = store
        current = apiBaseURL.absoluteString
    }

    /// Call once per launch, before the session's tokens are read. Records the
    /// current backend and returns `true` only when a *different* one was
    /// recorded before. A first run (nothing recorded yet, e.g. updating from a
    /// build that didn't record it) keeps the session, so existing Production
    /// users aren't signed out by this check.
    func environmentChanged() -> Bool {
        let previous = store.string(forKey: Self.storageKey)
        store.setString(current, forKey: Self.storageKey)
        return previous != nil && previous != current
    }
}
