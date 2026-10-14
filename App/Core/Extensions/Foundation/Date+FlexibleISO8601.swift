import Foundation

extension Date {
    /// Parses a server ISO 8601 timestamp that may or may not carry
    /// fractional seconds — `SONG_RESPONSE_SHAPE.md`'s own example
    /// (`"2024-01-10T08:30:00.000Z"`) has them, `JSONDecoder`'s built-in
    /// `.iso8601` strategy (a bare `ISO8601DateFormatter`) does not accept
    /// them. Same two-formatter fallback `User.swift` already carries
    /// privately for the same reason (auth's timestamps) — pulled out here
    /// rather than duplicated a third/fourth/fifth time now that the content
    /// domain models (T27) need it too; `User.swift` itself was left as-is
    /// rather than refactored onto this, since it already works and touching
    /// finished auth code for a pure dedup isn't worth the risk with no
    /// compiler to confirm the refactor.
    static func parseFlexibleISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatterWithFractionalSeconds.date(from: string) ?? isoFormatter.date(from: string)
    }

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
