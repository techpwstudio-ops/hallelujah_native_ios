import Foundation

/// A test/preview double — no Keychain access.
final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokens?

    func save(_ tokens: AuthTokens) throws {
        lock.lock()
        defer { lock.unlock() }
        self.tokens = tokens
    }

    func load() -> AuthTokens? {
        lock.lock()
        defer { lock.unlock() }
        return tokens
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        tokens = nil
    }
}
