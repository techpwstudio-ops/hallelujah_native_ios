import Foundation
import Security

/// Q4, both directions (progress.md): one Keychain item that this app and
/// the Flutter app (`lib/services/session_handoff_service.dart`) both keep
/// current with their session, so an App Store update from either build to
/// the other — including a future release built from the Flutter codebase
/// again — leaves the user signed in.
///
/// Each build rewrites the record at launch and after every change to its
/// tokens, user or membership, stamped with which build wrote it. A record
/// stamped by the *other* build at launch means that build ran last, so its
/// session is the current one:
///
/// - signed in there (same account, or nothing signed in here) → copied
///   into this build's stores;
/// - signed out there, or into a different account → this build signs out
///   through the normal path, so the old account's downloads and library
///   don't carry over.
///
/// No record at all is an update from a Flutter build that predates the
/// handoff — `LegacyFlutterSessionMigration` reads its Hive box instead.
///
/// The JSON both apps read and write — `user`/`membership` in the server's
/// wire shape, which both apps' models already decode:
///
///     {"version": 1, "writer": "native" | "flutter", "deviceId": "…",
///      "session": {"tokens": {"token": "…", "refreshToken": "…",
///                             "accessTokenExpiry": "<ISO 8601>",
///                             "refreshTokenExpiry": "<ISO 8601>"},
///                  "user": {…}, "membership": {…}}}
///
/// `session` absent or null = signed out.
final class SessionHandoff: @unchecked Sendable {
    /// Shared with the Flutter app (`IOSOptions(accountName:)` there) —
    /// changing it breaks the handoff.
    static let keychainService = "com.hallelujah.user.session-handoff"
    private static let writer = "native"

    private let tokenStore: any TokenStoring
    private let keyValueStore: any KeyValueStoring
    private let deviceIdentity: DeviceIdentityStore
    private let legacyMigration: LegacyFlutterSessionMigration
    private let logger = AppLogger(category: .security)
    private let lock = NSLock()
    /// Off until `syncAtLaunch()` has read the record — publishing before
    /// that would overwrite a session the other build left behind.
    private var publishing = false

    /// `tokenStore` is the plain Keychain store, not `publishing(_:)`'s
    /// wrapper — adopting a session must not publish half of it.
    init(
        tokenStore: any TokenStoring,
        keyValueStore: any KeyValueStoring = UserDefaultsKeyValueStore(),
        deviceIdentity: DeviceIdentityStore = .shared
    ) {
        self.tokenStore = tokenStore
        self.keyValueStore = keyValueStore
        self.deviceIdentity = deviceIdentity
        legacyMigration = LegacyFlutterSessionMigration(
            tokenStore: tokenStore,
            keyValueStore: keyValueStore,
            deviceIdentity: deviceIdentity
        )
    }

    /// Once per launch, before `Session`, `CurrentUserStore` and
    /// `MembershipStore` load. `true` when the local session must end
    /// through the normal sign-out — its tokens are already cleared.
    func syncAtLaunch() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            var endsLocalSession = false
            if let record = try readRecord(), record.writer != Self.writer {
                endsLocalSession = try adopt(record)
                legacyMigration.markCompleted()
            } else {
                // No record: an update from a Flutter build that predates it.
                // Or only this build's own — possibly a deleted copy's, since
                // Keychain items outlive the app — so it still runs once per
                // install.
                try legacyMigration.runIfNeeded()
            }
            publishing = true
            writeLocalSession()
            return endsLocalSession
        } catch {
            // The Keychain and the Flutter files stay unreadable until the
            // first unlock after a reboot — the next launch tries again.
            logger.warning("session handoff not readable yet, retrying next launch: \(error)")
            return false
        }
    }

    /// Records this build's current session for the other build.
    func publish() {
        lock.lock()
        defer { lock.unlock() }
        guard publishing else { return }
        writeLocalSession()
    }

    /// The other build's session is the current one. Returns whether this
    /// build's own session has to end instead of taking it over.
    private func adopt(_ record: Record) throws -> Bool {
        deviceIdentity.update(record.deviceId)
        let localUser = cached(User.self, forKey: CurrentUserStore.storageKey)
        let hasLocalSession = tokenStore.load() != nil && localUser != nil
        guard let incoming = record.session, !hasLocalSession || localUser?.id == incoming.user.id else {
            try tokenStore.clear()
            logger.info("signed out or switched account in the Flutter build — ending the local session")
            return hasLocalSession
        }

        try tokenStore.save(incoming.tokens)
        keyValueStore.setData(try? JSONEncoder().encode(incoming.user), forKey: CurrentUserStore.storageKey)
        if let membership = incoming.membership {
            keyValueStore.setData(try? JSONEncoder().encode(membership), forKey: MembershipStore.storageKey)
        } else if keyValueStore.data(forKey: MembershipStore.storageKey) != nil {
            // `MembershipStore.setMembership(nil)`: premium ended there.
            keyValueStore.removeValue(forKey: MembershipStore.storageKey)
            AudioQualitySelector.resetUserSelectedQuality(in: keyValueStore)
        }
        logger.info("session taken over from the Flutter build")
        return false
    }

    private func readRecord() throws -> Record? {
        guard let data = try HandoffKeychainItem.read() else { return nil }
        do {
            return try JSONDecoder.authTokens.decode(Record.self, from: data)
        } catch {
            // Overwritten with this build's own session right after.
            logger.warning("session handoff record unreadable, ignoring it: \(error)")
            return nil
        }
    }

    private func writeLocalSession() {
        let record = Record(writer: Self.writer, deviceId: deviceIdentity.deviceID, session: localSession())
        do {
            try HandoffKeychainItem.write(JSONEncoder.authTokens.encode(record))
        } catch {
            logger.warning("session handoff not written: \(error)")
        }
    }

    /// Signed in = tokens and a cached user, the same pair the splash
    /// routes on.
    private func localSession() -> Record.Snapshot? {
        guard let tokens = tokenStore.load(),
              let user = cached(User.self, forKey: CurrentUserStore.storageKey) else { return nil }
        return Record.Snapshot(
            tokens: tokens,
            user: user,
            membership: cached(Membership.self, forKey: MembershipStore.storageKey)
        )
    }

    private func cached<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        keyValueStore.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

extension SessionHandoff {
    /// `Session`'s token store, publishing after every save and clear.
    func publishing(_ base: any TokenStoring) -> any TokenStoring {
        PublishingTokenStore(base: base, handoff: self)
    }

    /// `CurrentUserStore`'s/`MembershipStore`'s storage, publishing after
    /// every write.
    func publishing(_ base: any KeyValueStoring) -> any KeyValueStoring {
        PublishingKeyValueStore(base: base, handoff: self)
    }
}

private struct Record: Codable {
    var version = 1
    let writer: String
    let deviceId: String?
    let session: Snapshot?

    struct Snapshot: Codable {
        let tokens: AuthTokens
        let user: User
        let membership: Membership?

        enum CodingKeys: String, CodingKey {
            case tokens, user, membership
        }

        init(tokens: AuthTokens, user: User, membership: Membership?) {
            self.tokens = tokens
            self.user = user
            self.membership = membership
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tokens = try container.decode(AuthTokens.self, forKey: .tokens)
            user = try container.decode(User.self, forKey: .user)
            // An unreadable membership loses premium until the next
            // `/users/me`, not the whole session.
            membership = try? container.decodeIfPresent(Membership.self, forKey: .membership)
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, writer, deviceId, session
    }

    init(writer: String, deviceId: String?, session: Snapshot?) {
        self.writer = writer
        self.deviceId = deviceId
        self.session = session
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        writer = try container.decode(String.self, forKey: .writer)
        deviceId = try? container.decodeIfPresent(String.self, forKey: .deviceId)
        // A session this build can't read counts as signed out — safer
        // than carrying on with a stale one.
        session = try? container.decodeIfPresent(Snapshot.self, forKey: .session)
    }
}

/// Written with the same attributes `flutter_secure_storage` matches on
/// (`IOSOptions(accessibility: first_unlock)`, not synchronizable), so
/// both apps find and update the same item.
private enum HandoffKeychainItem {
    static func read() throws -> Data? {
        var lookupQuery = query()
        lookupQuery[kSecReturnData as String] = true
        lookupQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandled(status)
        }
        return data
    }

    static func write(_ data: Data) throws {
        SecItemDelete(query() as CFDictionary) // SecItemAdd fails if the item already exists.

        var attributes = query()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SessionHandoff.keychainService,
            kSecAttrAccount as String: "session",
        ]
    }
}

private struct PublishingTokenStore: TokenStoring {
    let base: any TokenStoring
    let handoff: SessionHandoff

    func save(_ tokens: AuthTokens) throws {
        try base.save(tokens)
        handoff.publish()
    }

    func load() -> AuthTokens? {
        base.load()
    }

    func clear() throws {
        try base.clear()
        handoff.publish()
    }
}

private struct PublishingKeyValueStore: KeyValueStoring {
    let base: any KeyValueStoring
    let handoff: SessionHandoff

    func string(forKey key: String) -> String? { base.string(forKey: key) }
    func setString(_ value: String?, forKey key: String) { base.setString(value, forKey: key) }
    func bool(forKey key: String) -> Bool { base.bool(forKey: key) }
    func setBool(_ value: Bool, forKey key: String) { base.setBool(value, forKey: key) }
    func data(forKey key: String) -> Data? { base.data(forKey: key) }

    func setData(_ value: Data?, forKey key: String) {
        base.setData(value, forKey: key)
        handoff.publish()
    }

    func removeValue(forKey key: String) {
        base.removeValue(forKey: key)
        handoff.publish()
    }
}
