import Foundation

/// Dart's `getRefer()` / `_getRefer()` payload: `{initial, latest}` — the
/// link the app was first opened with and the most recent one
/// (`AppLinks().getInitialLinkString()` / `getLatestLinkString()`). Sent as
/// `refer` on `/auth/otp/send` and `/auth/oauth/verify` for install
/// attribution. Nil members are omitted from the encoded body.
struct ReferAttribution: Encodable, Sendable, Equatable {
    let initial: String?
    let latest: String?
}

/// Remembers the first and the latest inbound link for the process lifetime.
/// `DeepLinkService.receive(_:)` must call `record(_:)` for every URL it is
/// handed (lead-owned wiring; see the agent report).
final class ReferralAttributionStore: @unchecked Sendable {
    static let shared = ReferralAttributionStore()

    private let lock = NSLock()
    private var initial: String?
    private var latest: String?

    init() {}

    func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let value = url.absoluteString
        if initial == nil { initial = value }
        latest = value
    }

    /// `nil` when no link has ever been received (Dart still sends a map of
    /// two nulls; the server treats both the same).
    var snapshot: ReferAttribution? {
        lock.lock()
        defer { lock.unlock() }
        guard initial != nil || latest != nil else { return nil }
        return ReferAttribution(initial: initial, latest: latest)
    }
}
