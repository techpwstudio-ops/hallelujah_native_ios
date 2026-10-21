import Foundation
import Security

/// Q4 (progress.md): an App Store update from the Flutter build must not
/// sign anyone out. Same bundle ID, team and Keychain access group, so the
/// Flutter app's data is still on the device after the update — this copies
/// its session into the native stores on the first native launch, before
/// `Session`/`CurrentUserStore`/`MembershipStore` load them:
///
/// - `token`/`refreshToken`/expiries, `user` and `membership` from the
///   AES-encrypted Hive box (`Documents/secure_storage_box.hive`,
///   `StorageService` in `lib/services/storage_service.dart`), opened with
///   the `hive_encryption_key` Keychain item;
/// - the server-assigned `deviceId` Keychain item — carried over even when
///   signed out, since Dart's sign-out never clears it either.
///
/// For Flutter builds that predate `SessionHandoff`'s shared record, which
/// runs this whenever there's no record from the Flutter build to take
/// over instead. Read-only: the Flutter files are never changed. Runs once
/// per install, then marks itself done so a later native sign-out is never
/// undone by re-importing the old session — unless the data couldn't be
/// read yet (a launch before the first unlock after a reboot): it throws,
/// and the next launch tries again.
struct LegacyFlutterSessionMigration {
    static let completedKey = "legacyFlutterSession.migrated"

    private let tokenStore: any TokenStoring
    private let keyValueStore: any KeyValueStoring
    private let deviceIdentity: DeviceIdentityStore
    private let documentsDirectory: URL
    private let logger = AppLogger(category: .security)

    init(
        tokenStore: any TokenStoring,
        keyValueStore: any KeyValueStoring = UserDefaultsKeyValueStore(),
        deviceIdentity: DeviceIdentityStore = .shared,
        documentsDirectory: URL = .documentsDirectory
    ) {
        self.tokenStore = tokenStore
        self.keyValueStore = keyValueStore
        self.deviceIdentity = deviceIdentity
        self.documentsDirectory = documentsDirectory
    }

    func runIfNeeded() throws {
        guard !keyValueStore.bool(forKey: Self.completedKey) else { return }
        try migrate()
        markCompleted()
    }

    /// The Flutter build's handoff record superseded its Hive box.
    func markCompleted() {
        keyValueStore.setBool(true, forKey: Self.completedKey)
    }

    private func migrate() throws {
        let flutterDeviceID = try FlutterSecureStorage.value(forKey: "deviceId")
        if deviceIdentity.deviceID == nil {
            deviceIdentity.update(flutterDeviceID)
        }
        // Already signed in natively (e.g. a TestFlight build) — that session
        // wins. Tokens without a cached user belong to a copy of the app that
        // was deleted: Keychain items outlive it, UserDefaults don't.
        guard tokenStore.load() == nil || keyValueStore.data(forKey: CurrentUserStore.storageKey) == nil else { return }
        guard let box = try flutterBox() else { return }

        guard let accessToken = box["token"] as? String,
              let refreshToken = box["refreshToken"] as? String,
              let accessTokenExpiry = Date.parseFlexibleISO8601(box["accessTokenExpiry"] as? String),
              let refreshTokenExpiry = Date.parseFlexibleISO8601(box["refreshTokenExpiry"] as? String) else {
            logger.info("no Flutter session to migrate")
            return
        }
        // The splash only routes into the app with a cached user as well, so
        // tokens on their own would still land on sign-in.
        guard let user = decode(User.self, from: box["user"]) else {
            logger.warning("Flutter session has no readable user — not migrated")
            return
        }

        try tokenStore.save(AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiry: accessTokenExpiry,
            refreshTokenExpiry: refreshTokenExpiry
        ))
        // The id these tokens were issued to, over one a deleted copy left.
        deviceIdentity.update(flutterDeviceID)
        keyValueStore.setData(try? JSONEncoder().encode(user), forKey: CurrentUserStore.storageKey)
        if let membership = decode(Membership.self, from: box["membership"]) {
            keyValueStore.setData(try? JSONEncoder().encode(membership), forKey: MembershipStore.storageKey)
        }
        logger.info("Flutter session migrated")
    }

    /// `Hive.openBox('secure_storage_box')` under
    /// `getApplicationDocumentsDirectory()`. `nil` when there's no box (a
    /// fresh install) or no key to open it with.
    private func flutterBox() throws -> [String: Any]? {
        // Hive's `findHiveFileAndCleanUp`: a compaction interrupted before
        // its final rename leaves only the `.hivec`.
        let candidates = ["secure_storage_box.hive", "secure_storage_box.hivec"]
            .map { documentsDirectory.appendingPathComponent($0) }
        guard let boxURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        // `StorageService.init` stores the 32 key bytes as "12,250,…".
        guard let keyString = try FlutterSecureStorage.value(forKey: "hive_encryption_key") else { return nil }
        let key = keyString.split(separator: ",").compactMap { UInt8($0) }
        // Data protection keeps the file unreadable until the first unlock too.
        let data = try Data(contentsOf: boxURL)
        return FlutterHiveBox.entries(in: data, aesKey: key)
    }

    /// The box holds the server's `user`/`membership` maps as Dart decoded
    /// them — the same wire shape the native models decode.
    private func decode<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        guard let map = value as? [String: Any],
              JSONSerialization.isValidJSONObject(map),
              let data = try? JSONSerialization.data(withJSONObject: map) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// `flutter_secure_storage` 10.x items (darwin plugin 0.3.2, no Secure
/// Enclave): a generic password under the default `accountName` service,
/// the Dart key as the account, the value as UTF-8.
private enum FlutterSecureStorage {
    /// `nil` when there's no such item; throws when the Keychain can't be
    /// read right now (`errSecInteractionNotAllowed` before the first unlock).
    static func value(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "flutter_secure_storage_service",
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandled(status)
        }
        return String(data: data, encoding: .utf8)
    }
}
