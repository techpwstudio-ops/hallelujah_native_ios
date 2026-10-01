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
struct AdCreative {
    let adId: String
    let campaignId: String
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

    static func fromJSON(_ json: [String: Any]) -> AdCreative? {
        guard let adId = json["adId"] as? String,
              let campaignId = json["campaignId"] as? String,
              let placement = json["placement"] as? String,
              let assetType = json["assetType"] as? String,
              let impressionToken = json["impressionToken"] as? String
        else { return nil }

        return AdCreative(
            adId: adId,
            campaignId: campaignId,
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
    }
}

/// The CTA's destination, decided server-side rather than hardcoded per
/// placement in the client. `type` is either a `ShareableType` name (`song`,
/// `creator`, `playlist`, `userPlaylist`, `companyPlaylist`, `verseOfDay`)
/// for in-app content, `subscription` for the paywall, or `external` — see
/// `openAdAction(_:coordinator:)` for the fallback rule on anything else.
struct AdAction {
    let type: String
    /// Same free-form shape as `DeepLinkService.openShareable`'s own `item`
    /// parameter — only ever present alongside a `ShareableType` `type`.
    let item: [String: Any]?

    static func fromJSON(_ json: [String: Any]) -> AdAction {
        AdAction(type: json["type"] as? String ?? "external", item: json["item"] as? [String: Any])
    }
}

/// Placement-level pacing/rotation hints. Never hardcode these client-side —
/// they're admin-tunable, and the server is the one source of truth.
struct AdLoad: Sendable, Equatable {
    /// Organic items to show between ads for a pacing-style placement (e.g.
    /// the player ad-break). Nil where pacing doesn't apply.
    let pacingEveryN: Int?

    static func fromJSON(_ json: [String: Any]) -> AdLoad {
        AdLoad(pacingEveryN: json["pacingEveryN"] as? Int)
    }
}
