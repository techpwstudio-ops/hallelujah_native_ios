import Foundation
import Security

enum KeychainError: Error, Sendable {
    case unhandled(OSStatus)
}

/// Starts empty for users updating from the Flutter build; `SessionHandoff`
/// fills it from Flutter's session on their first native launch — from the
/// record both builds share, or, for a Flutter build older than that, from
/// its AES-encrypted Hive box (`LegacyFlutterSessionMigration`) — Q4 in
/// progress.md.
final class KeychainTokenStore: TokenStoring {
    private let service: String
    private let account = "session"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.hallelujah.user") {
        self.service = service
    }

    func save(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder.authTokens.encode(tokens)
        try? clear() // SecItemAdd fails if an item for this query already exists.

        var attributes = query()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    func load() -> AuthTokens? {
        var lookupQuery = query()
        lookupQuery[kSecReturnData as String] = true
        lookupQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder.authTokens.decode(AuthTokens.self, from: data)
    }

    func clear() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
