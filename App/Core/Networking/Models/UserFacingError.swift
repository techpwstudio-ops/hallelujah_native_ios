import Foundation

/// Turns any thrown error into copy that is safe to show a person. Swift's own
/// `localizedDescription` for a plain `Error` leaks type names
/// ("The operation couldn't be completed. (Hallelujah.AuthRepositoryError error 1.)"),
/// so UI code should call this instead.
enum UserFacingError {
    static var generic: String { String(localized: "Something went wrong. Please try again.") }
    static var offline: String { String(localized: "No internet connection. Please check your connection and try again.") }
    static var timedOut: String { String(localized: "The request timed out. Please try again.") }

    static func message(for error: Error) -> String {
        if error is CancellationError { return "" }

        if let apiError = error as? APIError {
            switch apiError {
            case let .transport(urlError): return message(for: urlError)
            case .decoding, .invalidResponse: return generic
            }
        }
        if let urlError = error as? URLError { return message(for: urlError) }

        // Only trust a description the type deliberately wrote for people.
        if error is LocalizedError, !error.localizedDescription.isEmpty,
           !error.localizedDescription.contains("Hallelujah") {
            return error.localizedDescription
        }
        return generic
    }

    private static func message(for urlError: URLError) -> String {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return offline
        case .timedOut:
            return timedOut
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return String(localized: "We couldn't reach the server. Please try again in a moment.")
        default:
            return generic
        }
    }
}
