import Foundation

/// Ports `AdCreative`/`AdAction`/`AdLoad` (`lib/ads/ad_creative.dart`) — one
/// served ad, parsed verbatim from `GET /ads/serve`'s 200 response.
///
/// A plain `fromJSON(_:)` factory over `[String: Any]`, not `Decodable`:
/// `AdAction.item` is the same free-form, one-shape-per-type payload
/// `DeepLinkService.openShareable` already parses for an incoming share
/// link (`song`/`creator`/`playlist`/… each have their own JSON shape) —
/// exactly why Dart's own `item` is typed `dynamic` rather than a fixed
/// class. Every other field is a plain optional/required scalar, matching
/// Dart's `fromJson` key-for-key.
///
/// `assetVariantUrls` is NOT modeled — grepped the whole ad break screen
/// surface (`ad_break_screen.dart`) for it: zero reads. It's a home-feed-only
/// field this task's player-only scope has no consumer for.
struct AdCreative: Sendable {
    let adId: String
    /// The advertiser's campaign, or nil for a company ad — the company's own
    /// promo, which belongs to no campaign. Identify "who is this from"
    /// (muting, one-per-page) with `campaignKey`, never this.
    let campaignId: String?
    let placement: String
    let assetType: String

    /// Already an absolute, signed URL through the backend's own proxy —
    /// load directly, never through `ArtworkURLResolver`'s own asset-key
    /// convention.
    let assetUrl: String?
    /// Same "already a URL" rule as `assetUrl` — the audio-ad companion
    /// image, or a `reel_video`'s own distinct companion if one exists.
    let companionImageUrl: String?
    let headline: String?
    let bodyText: String?
    let ctaLabel: String?
    let advertiserName: String?
    let advertiserLogoUrl: String?
    /// Same "already a URL" rule — fallback avatar when `advertiserLogoUrl`
    /// is null.
    let squareImageUrl: String?
    let durationSec: Int?
    /// Signed, tracked, 302-redirecting destination — open directly, no
    /// separate client-side click call needed for this path.
    let clickUrl: String?
    /// Echo this back via `AdsRepository.trackImpression` once genuinely
    /// visible on screen — never at fetch time.
    let impressionToken: String
    /// Seconds before the skip control unlocks, or nil if unskippable.
    let skipAfterSec: Int?
    let lingerAfterDismiss: Bool
    let adLoad: AdLoad
    /// Nil means every ad surface falls back to opening `clickUrl` directly.
    let action: AdAction?
    /// `kind == 'company'`: the company's own promo — free, never billed, and
    /// its token can't name a paid creative (no reactions/feedback to send).
    var isCompany: Bool = false

    /// `AdCreative.campaignKey` — the identity a listener's "stop showing
    /// this" and a page's "one of these per screen" both key on: the campaign
    /// for a paid ad, the promo itself for a company ad, with a prefix so the
    /// two id spaces can never collide.
    var campaignKey: String { campaignId ?? "company:\(adId)" }
    /// 16:9 picture the same campaign carries when it also has an image
    /// creative booked (`AdCreative.wideImageUrl`). Same "already a URL" rule.
    var wideImageUrl: String?

    static func fromJSON(_ json: [String: Any]) -> AdCreative? {
        guard let adId = json["adId"] as? String,
              let placement = json["placement"] as? String,
              let assetType = json["assetType"] as? String,
              let impressionToken = json["impressionToken"] as? String
        else { return nil }

        var creative = AdCreative(
            adId: adId,
            campaignId: json["campaignId"] as? String,
            placement: placement,
            assetType: assetType,
            assetUrl: json["assetUrl"] as? String,
            companionImageUrl: json["companionImageUrl"] as? String,
            headline: json["headline"] as? String,
            bodyText: json["bodyText"] as? String,
            ctaLabel: json["ctaLabel"] as? String,
            advertiserName: json["advertiserName"] as? String,
            advertiserLogoUrl: json["advertiserLogoUrl"] as? String,
            squareImageUrl: json["squareImageUrl"] as? String,
            durationSec: json["durationSec"] as? Int,
            clickUrl: json["clickUrl"] as? String,
            impressionToken: impressionToken,
            skipAfterSec: json["skipAfterSec"] as? Int,
            lingerAfterDismiss: json["lingerAfterDismiss"] as? Bool ?? false,
            adLoad: AdLoad.fromJSON(json["adLoad"] as? [String: Any] ?? [:]),
            action: (json["action"] as? [String: Any]).map(AdAction.fromJSON)
        )
        creative.isCompany = (json["kind"] as? String) == "company"
        creative.wideImageUrl = json["wideImageUrl"] as? String
        return creative
    }
}

/// The CTA's destination, decided server-side rather than hardcoded per
/// placement in the client. `type` is either a `ShareableType` name (`song`,
/// `creator`, `playlist`, `userPlaylist`, `companyPlaylist`, `verseOfDay`)
/// for in-app content, `subscription` for the paywall, or `external` — see
/// `openAdAction(_:coordinator:)` for the fallback rule on anything else.
struct AdAction: @unchecked Sendable {
    let type: String
    /// Free-form (`dynamic` in Dart): a `ShareableType` action carries the
    /// shape `DeepLinkService.openShareable` parses, a `deeplink` action our
    /// own share URL (a string), a `screen` action the tab key (a string).
    let item: Any?

    var itemObject: [String: Any]? { item as? [String: Any] }
    var itemString: String? { item as? String }

    static func fromJSON(_ json: [String: Any]) -> AdAction {
        AdAction(type: json["type"] as? String ?? "external", item: json["item"])
    }
}

/// Placement-level pacing/rotation hints. Never hardcode these client-side —
/// they're admin-tunable, and the server is the one source of truth.
struct AdLoad: Sendable, Equatable {
    /// Organic items to show between ads for a pacing-style placement (e.g.
    /// the player ad-break). Nil where pacing doesn't apply.
    let pacingEveryN: Int?
    /// The audio player image takeover's Intro / Ad / Gap seconds
    /// (`player_image_*` placements only); nil elsewhere or when the
    /// dashboard field is blank — read through `AdTimeline.resolve`.
    var introSeconds: Int?
    var displaySeconds: Int?
    var gapSeconds: Int?

    static func fromJSON(_ json: [String: Any]) -> AdLoad {
        AdLoad(
            pacingEveryN: json["pacingEveryN"] as? Int,
            introSeconds: json["introSeconds"] as? Int,
            displaySeconds: json["displaySeconds"] as? Int,
            gapSeconds: json["gapSeconds"] as? Int
        )
    }
}
