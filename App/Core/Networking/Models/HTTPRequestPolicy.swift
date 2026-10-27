import Foundation

/// The cross-cutting request rules `DioApi` (`lib/services/DioService.dart`)
/// applies per call through its `silent` / `retryable` flags and its response
/// interceptor — pulled out of `HTTPClient` as pure functions so they can be
/// unit tested without a network.
///
/// Dart decides these at each call site; `Endpoint` is a plain value with no
/// such flags, so the (small, fixed) set of Dart call sites that pass
/// `silent: true` / `retryable: false` is matched by path here instead.
enum HTTPRequestPolicy {
    // MARK: Silent requests

    /// Path prefixes / shapes whose Dart call sites pass `silent: true`
    /// (no user-facing toast for 429, 5xx or an exhausted retry): ads
    /// (`ads_repository.dart`), analytics upload, geo country
    /// (`country_service.dart`), library ids (`library_items/bloc.dart`),
    /// deep-link validation (`deep_link_service.dart`), related content
    /// (`related_content_service.dart`), bible search/chapter/snapshot calls,
    /// audit/client logs.
    private static let silentPrefixes = [
        "/ads/",
        "/analytics/",
        "/geo/country",
        "/library/items/ids",
        "/deep-link/",
        "/book/search",
        "/book/chapter/verses",
        "/book/snapshot/",
        "/system/public/audit",
        "/client-log",
    ]

    /// `true` for requests that must fail without a toast.
    static func isSilent(path: String) -> Bool {
        let bare = barePath(path)
        if silentPrefixes.contains(where: { bare.hasPrefix($0) }) { return true }
        let segments = bare.split(separator: "/").map(String.init)
        // `GET /song/:id` (`accessSongApi`, silent in the player and in the
        // deep-link/push open paths) and `GET /song/:id/related`.
        if segments.count == 2, segments[0] == "song" { return true }
        if segments.count == 3, segments[0] == "song", segments[2] == "related" { return true }
        return false
    }

    // MARK: Retry

    /// `kDioNoRetryKey`: a timed-out create may already have succeeded
    /// server-side, so resending it would duplicate the resource. The one
    /// Dart call site that opts out is `AiService.createConversation`
    /// (`POST /ai/conversations`).
    ///
    /// Also the user-playlist visibility/follow toggles, which Dart does
    /// retry: they are GETs that flip server state, so a resend after the
    /// response was lost flips it straight back and the user's change is
    /// silently undone.
    static func allowsRetry(method: HTTPMethod, path: String) -> Bool {
        let bare = barePath(path)
        if method == .post && bare == "/ai/conversations" { return false }
        return !isUserPlaylistToggle(bare)
    }

    /// `/library/user-playlist/:id/visibility` and `/library/user-playlist/:id/follow`.
    private static func isUserPlaylistToggle(_ bare: String) -> Bool {
        let segments = bare.split(separator: "/")
        return segments.count == 4
            && segments[0] == "library"
            && segments[1] == "user-playlist"
            && (segments[3] == "visibility" || segments[3] == "follow")
    }

    // MARK: Toasts

    /// `_ResponseInterceptor.onResponse`: 429 and 5xx get a generic toast.
    static func responseToast(statusCode: Int) -> String? {
        if statusCode == 429 { return String(localized: "Too many requests. Please try again later.") }
        if statusCode >= 500 { return String(localized: "Something went wrong. Please try again.") }
        return nil
    }

    /// `_RetryInterceptor`, once every attempt is spent: "No internet
    /// connection" when the device is actually offline, otherwise a timeout
    /// message.
    static func transportToast(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            String(localized: "No internet connection. Please check your network.")
        default:
            String(localized: "Connection timeout. Please try again.")
        }
    }

    // MARK: Error body normalisation

    /// `DioApi.normaliseErrorBody` / `_fallbackErrorMessage`.
    ///
    /// Returns replacement JSON bytes when an error response (status >= 400)
    /// does not already carry a JSON object, `nil` when the body must be left
    /// alone. A plain-text 429 from express-rate-limit, an HTML 502 page and
    /// an empty gateway-timeout body all become `{"message": ...}` so callers
    /// reading `message` never trip over a non-object body.
    static func normalisedErrorBody(_ data: Data, statusCode: Int) -> Data? {
        guard statusCode >= 400 else { return nil }

        var message: String?
        var raw: Any?

        if let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if parsed is [String: Any] { return nil }
            if let text = parsed as? String {
                message = usableMessage(from: text)
            } else if !(parsed is NSNull) {
                raw = parsed
            }
        } else if let text = String(data: data, encoding: .utf8) {
            message = usableMessage(from: text)
        }

        var body: [String: Any] = ["message": message ?? fallbackMessage(statusCode: statusCode)]
        if let raw { body["raw"] = raw }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    static func fallbackMessage(statusCode: Int) -> String {
        if statusCode == 429 { return String(localized: "Too many requests. Please try again later.") }
        if statusCode >= 500 { return String(localized: "Something went wrong. Please try again.") }
        return String(localized: "Request failed. Please try again.")
    }

    /// Non-empty, not an HTML page, and short enough to be a sentence.
    private static func usableMessage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<"), trimmed.count <= 300 else { return nil }
        return trimmed
    }

    private static func barePath(_ path: String) -> String {
        String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
}
