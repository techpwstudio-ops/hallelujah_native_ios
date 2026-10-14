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

            rememberPacing(placement, ad.adLoad.pacingEveryN)

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

    /// `AdServeGate` (`lib/ads/ad_serve_gate.dart`) — one request per
    /// placement-and-format at a time, and a remembered fill/no-fill verdict, so
    /// a feed that mounts eight rail slots in one frame sends one probe, not
    /// eight. Used by `serveThroughGate`.
    let serveGate = AdServeGate()

    /// `serve` behind `serveGate`: the entry point for surfaces that mount many
    /// slots at once (the home feed's rail and banner ads). Nil on no-fill, on
    /// any failure, or when the gate knows a request would be pointless.
    func serveThroughGate(placement: String, assetType: String? = nil) async -> AdCreative? {
        let key = AdServeGate.keyFor(placement, assetType)
        guard let turn = await serveGate.admit(key) else { return nil }
        defer { turn.failed() }
        let ad = await serve(placement: placement, assetType: assetType)
        if ad != nil { turn.filled() } else { turn.noFill() }
        return ad
    }

    private static func pacingStorageKey(_ placement: String) -> String {
        "ads_pacing_every_n:\(placement)"
    }

    /// The `adLoad.pacingEveryN` each placement reported this session.
    private var pacingEveryNByPlacement: [String: Int] = [:]

    /// `pacingEveryN` (Dart) — organic items between ads for `placement`, as
    /// the server last reported it (this session, else the copy saved by an
    /// earlier launch), or nil if it never has. A layout needs this BEFORE any
    /// slot has asked for a creative.
    func pacingEveryN(_ placement: String) -> Int? {
        if let live = pacingEveryNByPlacement[placement] { return live }
        let saved = UserDefaults.standard.integer(forKey: Self.pacingStorageKey(placement))
        return saved > 0 ? saved : nil
    }

    private func rememberPacing(_ placement: String, _ everyN: Int?) {
        guard let everyN, everyN > 0, pacingEveryNByPlacement[placement] != everyN else { return }
        pacingEveryNByPlacement[placement] = everyN
        UserDefaults.standard.set(everyN, forKey: Self.pacingStorageKey(placement))
    }

    /// Fire-and-forget: confirm `token`'s creative was genuinely rendered.
    /// Call once, only once a creative is actually on screen — never at
    /// serve time.
    func trackImpression(_ token: String) {
        Task {
            _ = try? await client.send(.post("/ads/track/impression"), body: try? JSONSerialization.data(withJSONObject: ["token": token]))
        }
    }

    /// `submitFeedback` — a mute kind keeps the campaign out of this session
    /// at once (`mutedCampaignIDs`); the server owns the durable suppression.
    /// Company ads have no paid token, so only the local mute applies.
    func submitFeedback(ad: AdCreative, kind: AdFeedbackKind, reason: String? = nil, note: String? = nil) {
        if kind.mutes { mutedCampaignIDs.insert(ad.campaignId) }
        guard !ad.isCompany else { return }
        var payload: [String: String] = ["token": ad.impressionToken, "kind": kind.wireValue]
        if let reason { payload["reason"] = reason }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { payload["note"] = note }
        Task {
            _ = try? await client.send(.post("/ads/feedback"), body: try? JSONSerialization.data(withJSONObject: payload))
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

/// `ads/ad_feedback.dart` — what a listener says about an ad from the ⋮ menu.
enum AdFeedbackKind: Sendable, Equatable {
    case interested
    case notInterested
    case report
    case close

    var wireValue: String {
        switch self {
        case .interested: "interested"
        case .notInterested: "not_interested"
        case .report: "report"
        case .close: "close"
        }
    }

    /// Whether this verdict keeps the campaign away from this listener.
    var mutes: Bool {
        switch self {
        case .notInterested, .report: true
        case .interested, .close: false
        }
    }
}

/// `AdFeedbackReasons` — the backend's vocabulary, keys not labels.
enum AdFeedbackReason: String, Sendable, CaseIterable {
    case notRelevant = "not_relevant"
    case seenTooOften = "seen_too_often"
    case dislikeBrand = "dislike_brand"
    case inappropriate, misleading, sexual, violence, copyright, broken, other

    /// `l10n.adReason*`.
    var label: String {
        switch self {
        case .notRelevant: "Not relevant to me"
        case .seenTooOften: "I've seen this too many times"
        case .dislikeBrand: "I don't like this brand"
        case .inappropriate: "Inappropriate or offensive"
        case .misleading: "Misleading or a scam"
        case .sexual: "Sexual content"
        case .violence: "Violence or dangerous content"
        case .copyright: "Copyright infringement"
        case .broken: "The ad didn't work properly"
        case .other: "Something else"
        }
    }

    /// The two lists `_showReasonSheet` offers, in Flutter's order.
    static func reasons(for kind: AdFeedbackKind) -> [AdFeedbackReason] {
        kind == .report
            ? [.inappropriate, .misleading, .sexual, .violence, .copyright, .broken, .other]
            : [.notRelevant, .seenTooOften, .dislikeBrand, .other]
    }
}
