import Foundation
import Security

enum KeychainError: Error, Sendable {
    case unhandled(OSStatus)
}

/// Reading the Flutter app's existing session on upgrade (so users aren't
/// forced to re-login) is deferred — see Q4 in progress.md. Flutter's token
/// isn't a plain Keychain item: it lives in an AES-encrypted Hive box, with
/// only the AES key in Keychain. This store starts empty for upgraders until
/// that migration is built.
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
