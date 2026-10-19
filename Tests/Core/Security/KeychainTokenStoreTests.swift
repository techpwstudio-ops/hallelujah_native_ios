import Foundation
import Testing
@testable import Hallelujah

struct KeychainTokenStoreTests {
    /// A service string distinct from the real app's — must never touch the
    /// actual signed-in user's Keychain entry.
    private let store = KeychainTokenStore(service: "com.hallelujah.user.tests.\(#file)")

    @Test func savedTokensRoundTripAndClearRemovesThem() throws {
        try store.clear() // leftover state from a previous failed run

        let tokens = AuthTokens(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            accessTokenExpiry: Date(timeIntervalSince1970: 2_000_000_000),
            refreshTokenExpiry: Date(timeIntervalSince1970: 2_100_000_000)
        )
        try store.save(tokens)
        #expect(store.load() == tokens)

        try store.clear()
        #expect(store.load() == nil)
    }
}
