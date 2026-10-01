import Foundation

/// Caches the signed-in user's `Membership`, mirroring `CurrentUserStore`
/// exactly — same actor shape, same `KeyValueStoring` persistence tier
/// (Dart's own counterpart, `OurSession.membership`/`setMembershipDetails`,
/// persists through the same `StorageService` tier `OurSession.user`
/// does — `session.dart`'s `_persist()` writes `user` and `membership` to
/// the same Hive box). `nil` is a valid, common state: most users have no
/// membership row at all, not an error.
///
/// Written to from the Data layer (`RemoteAuthRepository.fetchCurrentUser`/
/// `verifyOTP`/`verifySocialAuth`, and `StoreKitPurchaseManager` after a
/// verified purchase) before any view exists — an actor, not a
/// `@MainActor @Observable` store, for the same reason `CurrentUserStore`
/// is one (see its own doc comment).
actor MembershipStore {
    private(set) var membership: Membership?

    private let keyValueStore: any KeyValueStoring
    private static let storageKey = "currentMembership"

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
        if let data = keyValueStore.data(forKey: Self.storageKey) {
            membership = try? JSONDecoder().decode(Membership.self, from: data)
        }
    }

    func setMembership(_ membership: Membership?) {
        self.membership = membership
        guard let membership else {
            keyValueStore.removeValue(forKey: Self.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(membership) {
            keyValueStore.setData(data, forKey: Self.storageKey)
        }
    }

    func clear() {
        membership = nil
        keyValueStore.removeValue(forKey: Self.storageKey)
    }
}
