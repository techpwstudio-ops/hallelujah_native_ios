import Foundation

/// `AppErrorParser.parse` (`lib/utils/app_error_parser.dart`): maps low-level
/// failures to the user-facing strings the AI screens toast. An empty string
/// means a silently cancelled request (callers skip the toast).
@MainActor
enum AIErrorParser {
    static let genericMessage = "Something went wrong. Please try again."

    static func parse(_ error: Error, isOnline: Bool? = nil) -> String {
        if error is CancellationError { return "" }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return ""
            case .timedOut:
                return "Request timed out. Please try again."
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

    /// `_fromStatusCode` (the server's own `message` is not available on these
    /// errors, so the status-specific copy is used for every code).
    static func message(forStatus code: Int) -> String {
        switch code {
        case 400: return "Invalid request. Please try again."
        case 401: return "Session expired. Please sign in again."
        case 403: return "You don't have permission to do that."
        case 404: return "Content not found."
        case 429: return "You're sending messages too quickly. Please slow down and try again."
        case 500, 502, 503, 504: return "Something went wrong on our end. Please try again later."
        default: return genericMessage
        }
    }

    private static func connectionMessage(isOnline: Bool?) -> String {
        let online: Bool
        if let isOnline {
            online = isOnline
        } else {
            let reachability: (any ReachabilityMonitoring)? = DependencyContainer.current.resolveIfRegistered()
            online = reachability?.isOnline ?? true
        }
        return online
            ? "Connection failed. Please try again."
            : "No internet connection. Please check your connection and try again."
    }
}
