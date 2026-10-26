import Foundation

/// `AppErrorParser.parse` (`lib/utils/app_error_parser.dart`): maps low-level
/// failures to the user-facing strings the AI screens toast. An empty string
/// means a silently cancelled request (callers skip the toast).
@MainActor
enum AIErrorParser {
    static var genericMessage: String { String(localized: "Something went wrong. Please try again.") }

    static var offlineMessage: String {
        String(localized: "No internet connection. Please check your connection and try again.")
    }

    static func parse(_ error: Error, isOnline: Bool? = nil) -> String {
        if error is CancellationError { return "" }

        // `HTTPClient` (every non-streaming AI route: create conversation,
        // history, messages, suggestions) wraps URLSession's error, so it
        // must be unwrapped or an offline failure reads "Something went wrong".
        if let apiError = error as? APIError, case .transport(let urlError) = apiError {
            return parse(urlError, isOnline: isOnline)
        }

        // Whatever failed, with no connection the connection is the reason.
        if !(isOnline ?? ReachabilityBroadcast.shared.isOnline) {
            if let urlError = error as? URLError, urlError.code == .cancelled { return "" }
            return offlineMessage
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return ""
            case .timedOut:
                return String(localized: "Request timed out. Please try again.")
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                return connectionMessage(isOnline: isOnline)
            default:
                return genericMessage
            }
        }

        if let repositoryError = error as? AIChatRepositoryError, case .unexpectedStatus(let code) = repositoryError {
            return message(forStatus: code)
        }
        if let streamingError = error as? AIChatStreamingError, case .unexpectedStatus(let code) = streamingError {
            return message(forStatus: code)
        }

        return genericMessage
    }

    /// For screens with their own wording ("Couldn't load conversations"):
    /// the offline message when the device has no connection, else `fallback`.
    static func message(for error: Error, fallback: String) -> String {
        let parsed = parse(error)
        return parsed == offlineMessage ? offlineMessage : fallback
    }

    /// `_fromStatusCode` (the server's own `message` is not available on these
    /// errors, so the status-specific copy is used for every code).
    static func message(forStatus code: Int) -> String {
        switch code {
        case 400: return String(localized: "Invalid request. Please try again.")
        case 401: return String(localized: "Session expired. Please sign in again.")
        case 403: return String(localized: "You don't have permission to do that.")
        case 404: return String(localized: "Content not found.")
        case 429: return String(localized: "You're sending messages too quickly. Please slow down and try again.")
        case 500, 502, 503, 504: return String(localized: "Something went wrong on our end. Please try again later.")
        default: return genericMessage
        }
    }

    private static func connectionMessage(isOnline: Bool?) -> String {
        let online: Bool
        if let isOnline {
            online = isOnline
        } else {
            // A resolved monitor is never started and always reads online.
            online = ReachabilityBroadcast.shared.isOnline
        }
        return online ? String(localized: "Connection failed. Please try again.") : offlineMessage
    }
}
