import Foundation

enum SessionError: Error, Sendable {
    case noRefreshToken
    /// `OurSession.refreshIfNeeded`: the refresh token itself has lapsed, so
    /// there is nothing left to refresh with — the user must sign in again.
    case refreshTokenExpired
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
    private let deviceIdentity: DeviceIdentityStore
    private let headerProvider: RequestHeaderProvider
    private let logger = AppLogger(category: .security)

    private var tokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, any Error>?
    private var monitorTask: Task<Void, Never>?
    private var monitorStarted = false
    private var onLogout: (@Sendable () -> Void)?

    /// `_isExpiringSoon`'s `bufferSeconds` (`session.dart`).
    static let refreshBuffer: TimeInterval = 120
    /// `_restartTokenMonitor`: when already inside the window the timer fires
    /// after a brief pause instead of blocking the caller.
    static let monitorMinimumDelay: TimeInterval = 2
    /// `_onTokenRefreshTimerFire`: retry after a failed refresh.
    static let monitorRetryDelay: TimeInterval = 30

    init(
        tokenStore: any TokenStoring,
        refreshClient: HTTPClient,
        deviceIdentity: DeviceIdentityStore = .shared,
        headerProvider: RequestHeaderProvider = .shared
    ) {
        self.tokenStore = tokenStore
        self.refreshClient = refreshClient
        self.deviceIdentity = deviceIdentity
        self.headerProvider = headerProvider
        tokens = tokenStore.load()
    }

    /// Seconds until the proactive refresh should run: 2 minutes before the
    /// access token expires, or `monitorMinimumDelay` when that moment has
    /// already passed (`_restartTokenMonitor`).
    static func monitorDelay(accessExpiry: Date, now: Date = Date()) -> TimeInterval {
        let delay = accessExpiry.addingTimeInterval(-refreshBuffer).timeIntervalSince(now)
        return delay <= 0 ? monitorMinimumDelay : delay
    }

    /// Whether a failed refresh means the session is really over. Only a
    /// refusal from the server ends it; a network failure or a 5xx leaves the
    /// tokens alone (Dart's `refreshIfNeeded` swallows those and the monitor
    /// retries in 30 s) — logging out because the train went into a tunnel
    /// would be far worse than a delayed refresh.
    static func endsSession(after error: any Error) -> Bool {
        guard let sessionError = error as? SessionError else { return false }
        switch sessionError {
        case .noRefreshToken, .refreshTokenExpired:
            return true
        case .refreshFailed(let statusCode):
            return [401, 403, 404].contains(statusCode)
        }
    }

    func setOnLogout(_ handler: @escaping @Sendable () -> Void) {
        onLogout = handler
    }

    func currentAccessToken() -> String? {
        // `OurSession.token` calls `initSession()` on first read, which is
        // what arms the refresh timer on a cold start with a stored session.
        if !monitorStarted { startTokenMonitor() }
        return tokens?.accessToken
    }

    /// `refreshIfNeeded` before handing the token out, as Dart's request
    /// path does: right after launch (or an app update) the stored access
    /// token is usually stale, and the token monitor only refreshes it a
    /// couple of seconds later. Anything built in that window (the restored
    /// player queue) carried a dead token and kept failing. A failed refresh
    /// still returns the current token; callers fall back to their 401 path.
    func validAccessToken() async -> String? {
        if tokens != nil, isAccessTokenExpired() {
            _ = try? await refreshIfNeeded()
        }
        return currentAccessToken()
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
        defer { startTokenMonitor() }
        try tokenStore.save(newTokens)
    }

    func logout() {
        tokens = nil
        monitorTask?.cancel()
        monitorTask = nil
        monitorStarted = false
        try? tokenStore.clear()
        // `DioApi.logout()`: the next account fetches its own App Check token.
        headerProvider.reset()
        logger.info("session logged out")
        SessionTeardown.perform()
        onLogout?()
    }

    // MARK: Token monitor

    /// `OurSession._restartTokenMonitor`: one single-shot timer that wakes
    /// 2 minutes before the access token expires — no polling. A refresh
    /// token that has already lapsed logs out immediately. Re-armed by
    /// `store(_:)`, so a successful refresh chains the next wake-up.
    func startTokenMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
        monitorStarted = true
        guard let tokens else { return }

        if Date() > tokens.refreshTokenExpiry {
            logger.info("refresh token expired — logging out")
            logout()
            return
        }
        scheduleMonitor(after: Self.monitorDelay(accessExpiry: tokens.accessTokenExpiry))
    }

    private func scheduleMonitor(after delay: TimeInterval) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.monitorFired()
        }
    }

    /// `_onTokenRefreshTimerFire`: refresh when inside the expiry window;
    /// otherwise (clock skew) re-arm. A failed refresh retries in 30 s so
    /// monitoring never silently stops.
    private func monitorFired() async {
        guard tokens != nil else { return }
        guard isAccessTokenExpired() else {
            startTokenMonitor()
            return
        }
        do {
            try await refreshIfNeeded()
        } catch {
            if tokens != nil {
                scheduleMonitor(after: Self.monitorRetryDelay)
            }
        }
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
        // `refreshIfNeeded`: a lapsed refresh token cannot be exchanged.
        if let refreshExpiry = tokens?.refreshTokenExpiry, Date() > refreshExpiry {
            logout()
            throw SessionError.refreshTokenExpired
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
            if Self.endsSession(after: error) {
                logout()
            }
            throw error
        }
    }

    private func performRefresh(refreshToken: String) async throws -> AuthTokens {
        let body = try JSONEncoder().encode(["refreshToken": refreshToken])
        let response = try await refreshClient.send(.refreshToken, body: body)
        guard response.statusCode == 200 else {
            throw SessionError.refreshFailed(statusCode: response.statusCode)
        }
        let refreshed = try JSONDecoder.authTokens.decode(AuthTokens.self, from: response.data)
        // `createSession(deviceId:)` runs on refresh too, and only overwrites
        // the stored id when the response carries one.
        if let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
            deviceIdentity.update(object["deviceId"] as? String)
        }
        return refreshed
    }
}
