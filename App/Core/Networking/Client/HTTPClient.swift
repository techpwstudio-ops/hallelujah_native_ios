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
    private let logger = AppLogger(category: .networking)

    init(
        configuration: AppConfiguration = .current,
        authProvider: (any AuthTokenProviding)? = nil,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        self.authProvider = authProvider
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            // Dio: connectTimeout 10s / receiveTimeout 30s / sendTimeout 60s.
            // URLSession has no separate connect-timeout knob; timeoutIntervalForRequest
            // (max idle time waiting for data) is the closest match to receiveTimeout.
            sessionConfiguration.timeoutIntervalForRequest = 30
            sessionConfiguration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    /// On a 401, triggers exactly one (single-flight) refresh via
    /// `authProvider` and replays this request once with the new token —
    /// it does not loop further if the replay is also a 401.
    func send(_ endpoint: Endpoint, body: Data? = nil) async throws -> HTTPResponse {
        let request = try await makeRequest(for: endpoint, body: body)
        let response = try await send(request, endpoint: endpoint, attempt: 0)

        guard response.statusCode == 401, let authProvider else {
            return response
        }

        do {
            try await authProvider.refreshIfNeeded()
        } catch {
            return response // refresh failed; authProvider already logged out
        }

        let retriedRequest = try await makeRequest(for: endpoint, body: body)
        return try await send(retriedRequest, endpoint: endpoint, attempt: 0)
    }

    private func send(_ request: URLRequest, endpoint: Endpoint, attempt: Int) async throws -> HTTPResponse {
        logger.debug("\(endpoint.method.rawValue) \(endpoint.path) — attempt \(attempt + 1)/\(Self.maxAttempts)")
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            logger.debug("\(endpoint.method.rawValue) \(endpoint.path) — status \(httpResponse.statusCode)")
            return HTTPResponse(statusCode: httpResponse.statusCode, data: data)
        } catch let error as URLError where Self.isRetryable(error) && attempt < Self.maxAttempts - 1 {
            let delayMilliseconds = 500 * (attempt + 1)
            logger.warning("\(endpoint.path) failed (\(error.code.rawValue)), retrying in \(delayMilliseconds)ms")
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            return try await send(request, endpoint: endpoint, attempt: attempt + 1)
        } catch let error as URLError {
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
        let token = await authProvider?.currentAccessToken() ?? ""
        return [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": "Bearer \(token)",
            "secure": configuration.apiSecureHeader,
            // Dio's `buildHeaders()` sends this on every request; several
            // endpoints branch on it server-side (`getPremiumPlans`/
            // `createPaymentRequest`, T61 — `req.headers["os"]` resolves
            // `platform`, which is what resolves `providerPlanId` to a real
            // Apple product ID; omitting it silently defaults `platform`
            // to `"web"` and no plan ever becomes purchasable). Hardcoded
            // literal, not a per-platform switch — this target only ships iOS.
            "os": "ios",
            // device-id/device-model/app-version/build-number/app-check-token
            // (buildHeaders() in DioService.dart) land as their sources do:
            // device info, then Firebase App Check in T15.
        ]
    }
}
