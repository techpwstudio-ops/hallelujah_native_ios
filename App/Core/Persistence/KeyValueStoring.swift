import Foundation

/// Small typed settings/flags — not for tokens (Keychain, see
/// `TokenStoring`) and not for cacheable content (`Database`/`DiskCache`).
protocol KeyValueStoring: Sendable {
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
    func bool(forKey key: String) -> Bool
    func setBool(_ value: Bool, forKey key: String)
    /// Small JSON blobs only (e.g. `CurrentUserStore`'s cached `User`) —
    /// mirrors Dart's `StorageService.getMap`/`setMap` (Hive-backed), the
    /// tier `OurSession.user` persists to, distinct from the Keychain tier
    /// `Session`/`TokenStoring` use for tokens. Not for anything large or
    /// structured enough to want `Database`.
    func data(forKey key: String) -> Data?
    func setData(_ value: Data?, forKey key: String)
    func removeValue(forKey key: String)
}
