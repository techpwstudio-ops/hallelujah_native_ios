import Foundation

/// Caches the signed-in `User`, mirroring `OurSession.user`/`setUser`
/// (`lib/utils/session.dart`) — persisted through `KeyValueStoring` (the
/// same tier Dart's `StorageService` uses for `user`, distinct from the
/// Keychain tier `Session`/`TokenStoring` use for tokens), so a cold
/// relaunch has an immediate, un-refreshed `user` to show rather than
/// waiting on the first `/users/me` round-trip.
///
/// An actor, not a `@MainActor @Observable` view-facing store like T19's
/// `NetworkStatusStore`: this is written to from the Data layer
/// (`RemoteAuthRepository`) before any view exists, so it needs the same
/// "constructed once by `AppComposition`, safe to call from any context"
/// shape as `Session` — not a `@State`-owned, shell-lifetime store. A
/// SwiftUI-facing wrapper (mirroring how `NetworkStatusStore` bridges
/// `ReachabilityMonitoring` into `@Observable`) is T21-24's concern once a
/// view actually needs to react to sign-in state, not this task's.
actor CurrentUserStore {
    private(set) var user: User?

    private let keyValueStore: any KeyValueStoring
    private static let storageKey = "currentUser"

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
        if let data = keyValueStore.data(forKey: Self.storageKey) {
            user = try? JSONDecoder().decode(User.self, from: data)
        }
    }

    func setUser(_ user: User) {
        self.user = user
        if let data = try? JSONEncoder().encode(user) {
            keyValueStore.setData(data, forKey: Self.storageKey)
        }
    }

    func clear() {
        user = nil
        keyValueStore.removeValue(forKey: Self.storageKey)
    }
}
