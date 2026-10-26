import Foundation

/// URLSession-based HTTP client mirroring the Flutter app's `DioApi`
/// (`lib/services/DioService.dart`): same base URLs (`AppConfiguration`),
/// same static headers, same retry policy — 3 attempts total, retrying
/// transport failures only, never an HTTP status.
///
/// Backoff is `500ms * attempt` (500ms, then 1000ms), from Dio's actual
/// `_RetryInterceptor` formula (`DioService.dart:485`) — its own doc comment
/// claims 500ms/1500ms, but that comment doesn't match the code it's
/// documenting; this follows the formula, not the stale comment.
///
/// `Authorization` comes from `authProvider` — nil for the plain client
/// `Session` itself uses to call the refresh endpoint (see `Session.swift`
/// for why that client must not recurse back into auth handling).
final class HTTPClient: Sendable {
    static let maxAttempts = 3

    private let session: URLSession
    private let configuration: AppConfiguration
    private let authProvider: (any AuthTokenProviding)?
    private let headerProvider: RequestHeaderProvider
    private let logger = AppLogger(category: .networking)

    init(
        configuration: AppConfiguration = .current,
        authProvider: (any AuthTokenProviding)? = nil,
        session: URLSession? = nil,
        headerProvider: RequestHeaderProvider = .shared
    ) {
        self.configuration = configuration
        self.authProvider = authProvider
        self.headerProvider = headerProvider
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            // Dio: connectTimeout 10s / receiveTimeout 30s / sendTimeout 60s.
            // URLSession has no separate connect-timeout knob; timeoutIntervalForRequest
            // (max idle time waiting for data) is the closest match to receiveTimeout.
            sessionConfiguration.timeoutIntervalForRequest = 30
            sessionConfiguration.timeoutIntervalForResource = 60
            // Dio keeps no HTTP cache; URLSession's default one can answer a
            // GET from disk (several "write" routes are GETs, e.g. the
            // playlist visibility/follow toggles) or hand back a page fetched
            // before a change. Every API call goes to the server.
            sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
            sessionConfiguration.urlCache = nil
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    /// On a 401, triggers exactly one (single-flight) refresh via
    /// `authProvider` and replays this request once with the new token —
    /// it does not loop further if the replay is also a 401.
    ///
    /// Response handling mirrors `DioApi`'s `_ResponseInterceptor`: an error
    /// status (>= 400) whose body is not a JSON object is rewritten to
    /// `{"message": ...}` so callers can always read `message`, and 429 / 5xx
    /// raise the generic toast unless the request is silent
    /// (`HTTPRequestPolicy`). The 401 replay is not toasted twice — only the
    /// response the caller finally receives is.
    ///
    /// `silent` overrides `HTTPRequestPolicy.isSilent(path:)` for one call —
    /// Dart's per-call `silent:` flag (a background retry of a request that is
    /// normally user-visible passes `true`).
    func send(_ endpoint: Endpoint, body: Data? = nil, silent: Bool? = nil) async throws -> HTTPResponse {
        let isSilent = silent ?? HTTPRequestPolicy.isSilent(path: endpoint.path)
        let request = try await makeRequest(for: endpoint, body: body)
        var response = try await send(request, endpoint: endpoint, attempt: 0, silent: isSilent)

        if response.statusCode == 401, let authProvider {
            var refreshed = false
            do {
                try await authProvider.refreshIfNeeded()
                refreshed = true
            } catch {
                // Refresh failed; authProvider already logged out when that
                // was the right call. The original 401 is what the caller sees.
            }
            if refreshed {
                let retriedRequest = try await makeRequest(for: endpoint, body: body)
                response = try await send(retriedRequest, endpoint: endpoint, attempt: 0, silent: isSilent)
            }
        }

        return finalised(response, silent: isSilent)
    }

    private func finalised(_ response: HTTPResponse, silent: Bool) -> HTTPResponse {
        var result = response
        if let normalised = HTTPRequestPolicy.normalisedErrorBody(response.data, statusCode: response.statusCode) {
            result = HTTPResponse(statusCode: response.statusCode, data: normalised)
        }
        if !silent, let message = HTTPRequestPolicy.responseToast(statusCode: response.statusCode) {
            Self.showToast(message)
        }
        return result
    }

    private static func showToast(_ message: String) {
        Task { @MainActor in ToastCenter.shared.show(message) }
    }

    private func send(_ request: URLRequest, endpoint: Endpoint, attempt: Int, silent: Bool) async throws -> HTTPResponse {
        logger.debug("\(endpoint.method.rawValue) \(endpoint.path) — attempt \(attempt + 1)/\(Self.maxAttempts)")
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            logger.debug("\(endpoint.method.rawValue) \(endpoint.path) — status \(httpResponse.statusCode)")
            return HTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as URLError where Self.isRetryable(error)
            && HTTPRequestPolicy.allowsRetry(method: endpoint.method, path: endpoint.path)
            && attempt < Self.maxAttempts - 1 {
            let delayMilliseconds = 500 * (attempt + 1)
            logger.warning("\(endpoint.path) failed (\(error.code.rawValue)), retrying in \(delayMilliseconds)ms")
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            return try await send(request, endpoint: endpoint, attempt: attempt + 1, silent: silent)
        } catch let error as URLError {
            // Every attempt spent (or not retryable): `_RetryInterceptor`'s
            // closing toast. A cancelled request is the caller's own doing.
            if error.code != .cancelled, Self.isRetryable(error), !silent {
                Self.showToast(HTTPRequestPolicy.transportToast(for: error))
            }
            throw APIError.transport(error)
        }
    }

    /// Connection timeout / receive timeout / send timeout / connection error —
    /// never a 4xx/5xx HTTP status, which URLSession doesn't surface as a thrown
    /// error in the first place (see `HTTPResponse`/`APIError` doc comments).
    private static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    private func makeRequest(for endpoint: Endpoint, body: Data?) async throws -> URLRequest {
        let baseURL = switch endpoint.base {
        case .api: configuration.apiBaseURL
        case .proxy: configuration.proxyBaseURL
        }
        // Plain string concatenation, not URL(string:relativeTo:) — a path
        // starting with "/" would otherwise replace baseURL's own "/api"
        // path component instead of appending to it.
        guard let url = URL(string: baseURL.absoluteString + endpoint.path) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = body
        request.allHTTPHeaderFields = await headers()
        return request
    }

    private func headers() async -> [String: String] {
        let token = await authProvider?.validAccessToken() ?? ""
        // `buildHeaders()` (`DioService.dart`): app-check-token, device-id,
        // device-model, os, app-version, build-number. Several endpoints
        // branch on `os` server-side (`getPremiumPlans`/
        // `createPaymentRequest` resolve `providerPlanId` to a real Apple
        // product ID from it — omitting it silently defaults the platform to
        // `"web"` and no plan ever becomes purchasable).
        var headers = await headerProvider.headers()
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json"
        headers["Authorization"] = "Bearer \(token)"
        headers["secure"] = configuration.apiSecureHeader
        return headers
    }
}
