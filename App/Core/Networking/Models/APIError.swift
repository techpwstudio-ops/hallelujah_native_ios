import Foundation

/// Thrown only for transport-level failures (no connection, timeout, DNS,
/// decode) — mirroring Dio's `validateStatus: (_) => true`, an HTTP error
/// status (4xx/5xx) is a normal, non-throwing `HTTPResponse` the caller
/// inspects, not an `APIError`.
enum APIError: Error, Sendable {
    case transport(URLError)
    case decoding(String)
    case invalidResponse
}
