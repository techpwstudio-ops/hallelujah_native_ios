/// What `HTTPClient` needs from a session to inject `Authorization` and
/// react to a 401 — kept as a protocol so Core/Networking doesn't depend on
/// the concrete `Session` type in Core/Security.
protocol AuthTokenProviding: Sendable {
    func currentAccessToken() async -> String?

    /// Single-flight: concurrent callers all await the same in-flight
    /// refresh. Logs the session out (clearing stored tokens) on failure.
    @discardableResult
    func refreshIfNeeded() async throws -> AuthTokens
}
