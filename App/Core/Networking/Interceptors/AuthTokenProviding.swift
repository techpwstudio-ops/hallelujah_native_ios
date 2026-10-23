/// What `HTTPClient` needs from a session to inject `Authorization` and
/// react to a 401 — kept as a protocol so Core/Networking doesn't depend on
/// the concrete `Session` type in Core/Security.
protocol AuthTokenProviding: Sendable {
    func currentAccessToken() async -> String?

    /// Single-flight: concurrent callers all await the same in-flight
    /// refresh. Logs the session out (clearing stored tokens) on failure.
    @discardableResult
    func refreshIfNeeded() async throws -> AuthTokens

    /// The access token, refreshed first when it has expired (or is inside
    /// its last two minutes). For anything that hands the token to a
    /// request it can't replay on a 401 itself: AVPlayer, downloads,
    /// artwork.
    func validAccessToken() async -> String?
}

extension AuthTokenProviding {
    func validAccessToken() async -> String? {
        await currentAccessToken()
    }
}
