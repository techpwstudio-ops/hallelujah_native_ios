import Foundation

/// Ports `AdsRepository` (`lib/ads/ads_repository.dart`) — talks to
/// `/ads/*`. Mirrors that file's own central contract: an ads problem must
/// never become a visible app defect, so `serve` resolves every failure
/// (remote kill switch, premium, local backoff, network error, malformed
/// payload, muted campaign) to `nil` rather than throwing — a deliberate
/// departure from this codebase's usual throwing-repository convention
/// (`RemoteSubscriptionRepository` etc.), justified the same way Dart's own
/// file justifies it.
///
/// `@MainActor`, not an `actor` — matches `MembershipStore`/`QueueController`'s
/// own class-not-actor idiom, and the one real caller (`AdPacingController`)
/// is itself `@MainActor`.
///
/// **The premium check lives here** (`serve`, right after the `adsEnabled`
/// gate): `PremiumGate.showsAds` (T65's single source of truth) skips
/// serving entirely. This is the one gate T69 needed and T65 (Premium
/// gating, deferred to a later batch) does not yet exist to centralize —
/// `Subscription.isActive` is the same entitlement `SettingsView`/T61 already
/// read for every other premium restriction, so this is not a new, separately
/// invented notion of "premium."
@MainActor
final class AdsRepository {
    private let client: HTTPClient
    private let premiumGate: PremiumGate
    private let logger = AppLogger(category: .ads)

    /// `_retryNotBefore` (Dart) — keyed by `placement[:assetType]`, same
    /// per-format-not-just-per-placement reasoning as that file's own doc
    /// comment. Always backs off the fixed default below: `HTTPResponse`
    /// (`App/Core/Networking/Client/HTTPResponse.swift`) carries no response
    /// headers today, so the server's own `Retry-After` hint — Dart's
    /// preferred source — isn't readable here without widening that shared
    /// type for every other repository too. Flagged, not silently guessed.
    private var retryNotBefore: [String: Date] = [:]
    private static let defaultRetryBackoff: TimeInterval = 60

    /// `_mutedCampaignIds` (Dart) — session-local only; the server-side mute
    /// is the durable copy. Nothing in this task's scope writes to this set
    /// yet (`submitFeedback`/the mute sheet is cut — see this task's status-
    /// log entry), so it only ever matters once something does.
    private var mutedCampaignIDs: Set<String> = []

    init(client: HTTPClient, membershipStore: MembershipStore) {
        self.client = client
        premiumGate = PremiumGate(membershipStore: membershipStore)
    }

    /// Requests one ad for `placement`, or nil on no-fill/any failure.
    func serve(
        placement: String,
        platform: String? = nil,
        country: String? = nil,
        assetType: String? = nil,
        ignoreRetryBackoff: Bool = false
    ) async -> AdCreative? {
        guard RemoteSettings.current.adsEnabled else {
            logger.debug("ads:skip placement=\(placement) reason=adsEnabled=false")
            return nil
        }

        if await !premiumGate.showsAds {
            logger.debug("ads:skip placement=\(placement) reason=isPremium=true")
            return nil
        }

        let retryKey = assetType.map { "\(placement):\($0)" } ?? placement
        if !ignoreRetryBackoff, let notBefore = retryNotBefore[retryKey], Date() < notBefore {
            logger.debug("ads:skip placement=\(placement) reason=retryBackoff notBefore=\(notBefore)")
            return nil
        }

        var path = "/ads/serve?placement=\(placement)"
        if let platform { path += "&platform=\(platform)" }
        if let country { path += "&country=\(country)" }
        if let assetType { path += "&assetType=\(assetType)" }

        do {
            let response = try await client.send(.get(path))
            guard response.statusCode == 200 else {
                retryNotBefore[retryKey] = Date().addingTimeInterval(Self.defaultRetryBackoff)
                logger.debug("ads:no-fill placement=\(placement) status=\(response.statusCode)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let ad = AdCreative.fromJSON(json)
            else {
                logger.debug("ads:error placement=\(placement) reason=malformedPayload")
                return nil
            }

            if mutedCampaignIDs.contains(ad.campaignId) {
                logger.debug("ads:skip placement=\(placement) reason=mutedCampaign campaignId=\(ad.campaignId)")
                return nil
            }
            logger.debug("ads:served placement=\(placement) adId=\(ad.adId) campaignId=\(ad.campaignId)")
            return ad
        } catch {
            logger.debug("ads:error placement=\(placement) error=\(error)")
            return nil
        }
    }

    /// Fire-and-forget: confirm `token`'s creative was genuinely rendered.
    /// Call once, only once a creative is actually on screen — never at
    /// serve time.
    func trackImpression(_ token: String) {
        Task {
            _ = try? await client.send(.post("/ads/track/impression"), body: try? JSONSerialization.data(withJSONObject: ["token": token]))
        }
    }

    /// `_reactions` (Dart) — the thumb each served creative currently shows,
    /// keyed by impression token. Session-local.
    private var reactions: [String: AdReaction] = [:]

    func reaction(for ad: AdCreative) -> AdReaction? { reactions[ad.impressionToken] }

    /// `AdsRepository.react` — remembered locally first so the thumb lights on
    /// the frame it's pressed, then a silent fire-and-forget
    /// `POST /ads/reaction`; `nil` takes the thumb back (`"none"`).
    func react(to ad: AdCreative, _ reaction: AdReaction?) {
        reactions[ad.impressionToken] = reaction
        // A company ad's token can't name a paid creative: lit locally only.
        guard !ad.isCompany else { return }
        let payload: [String: String] = [
            "token": ad.impressionToken,
            "reaction": reaction?.wireValue ?? AdReaction.clearWireValue,
        ]
        Task {
            _ = try? await client.send(.post("/ads/reaction"), body: try? JSONSerialization.data(withJSONObject: payload))
        }
    }

    /// Fire-and-forget: record a tap on `token`'s creative. Only call this
    /// for a CTA opened in-app — an external `clickUrl`'s own signed redirect
    /// already records the click server-side.
    func trackClick(_ token: String) {
        Task {
            _ = try? await client.send(.post("/ads/track/click"), body: try? JSONSerialization.data(withJSONObject: ["token": token]))
        }
    }
}

/// `ads/ad_reaction.dart` — a listener's thumb on an ad. Wire values are the
/// backend's, spelled out rather than derived from the case name.
enum AdReaction: Sendable, Equatable {
    case like
    case dislike

    static let clearWireValue = "none"

    var wireValue: String {
        switch self {
        case .like: "like"
        case .dislike: "dislike"
        }
    }

    /// `nextReaction`: pressing the lit thumb takes it back; the other switches.
    static func next(current: AdReaction?, tapped: AdReaction) -> AdReaction? {
        current == tapped ? nil : tapped
    }
}
