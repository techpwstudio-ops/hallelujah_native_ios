import Foundation

enum SessionError: Error, Sendable {
    case noRefreshToken
    case refreshFailed(statusCode: Int)
}

/// Owns the current tokens, persists them via `TokenStoring`, and coordinates
/// refresh so concurrent 401s share a single in-flight `/auth/token/refresh`
/// call (`lib/utils/session.dart`'s `_refreshing` flag, done with actor
/// isolation instead of a bool).
actor Session: AuthTokenProviding {
    private let tokenStore: any TokenStoring
    /// A plain client with no `authProvider` — using the authenticated client
    /// here would let a 401 from the refresh call itself recurse back into
    /// `refreshIfNeeded()`.
    private let refreshClient: HTTPClient
    private let logger = AppLogger(category: .security)

    private var tokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, any Error>?
    private var onLogout: (@Sendable () -> Void)?

    init(tokenStore: any TokenStoring, refreshClient: HTTPClient) {
        self.tokenStore = tokenStore
        self.refreshClient = refreshClient
        tokens = tokenStore.load()
    }

    func setOnLogout(_ handler: @escaping @Sendable () -> Void) {
        onLogout = handler
    }

    func currentAccessToken() -> String? {
        tokens?.accessToken
    }

    /// Matches Dart's `_isExpiringSoon` buffer (`lib/utils/session.dart`,
    /// default `bufferSeconds: 120`): expired the moment it enters its last
    /// 2 minutes, not only once it actually lapses. No tokens at all counts
    /// as expired, same as Dart's `isAccessTokenExpired` treating a null
    /// expiry as `true`.
    func isAccessTokenExpired() -> Bool {
        guard let expiry = tokens?.accessTokenExpiry else { return true }
        return Date().addingTimeInterval(120) >= expiry
    }

    func store(_ newTokens: AuthTokens) throws {
        tokens = newTokens
        try tokenStore.save(newTokens)
    }

    func logout() {
        tokens = nil
        try? tokenStore.clear()
        logger.info("session logged out")
        onLogout?()
    }

    @discardableResult
    func refreshIfNeeded() async throws -> AuthTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let currentRefreshToken = tokens?.refreshToken else {
            logout()
            throw SessionError.noRefreshToken
        }

        logger.debug("refreshing access token")
        let task = Task { try await self.performRefresh(refreshToken: currentRefreshToken) }
        refreshTask = task

        do {
            let newTokens = try await task.value
            refreshTask = nil
            try store(newTokens)
            logger.debug("refresh succeeded")
            return newTokens
        } catch {
            refreshTask = nil
            logger.warning("refresh failed: \(error)")
            logout()
            throw error
        }
    }

    private func performRefresh(refreshToken: String) async throws -> AuthTokens {
        let body = try JSONEncoder().encode(["refreshToken": refreshToken])
        let response = try await refreshClient.send(.refreshToken, body: body)
        guard response.statusCode == 200 else {
            throw SessionError.refreshFailed(statusCode: response.statusCode)
        }
        return try JSONDecoder.authTokens.decode(AuthTokens.self, from: response.data)
    }
}
