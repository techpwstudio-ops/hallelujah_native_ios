import Foundation

/// Ports `lib/ads/ad_break_fill.dart` — which ads an ad break asks for, on which
/// placement, and what counts as something a break can play.
///
/// Pure on purpose: `AdPacingController` owns the player and the timing, this
/// owns the decisions, so they are tested without either.
enum AdBreakFill {
    /// The only formats an ad break can play: a soundtrack or a video. Ordered,
    /// because `assetType(atTurn:)` rotates through them.
    static let assetTypes = ["audio_ad", "reel_video"]

    /// The placement an `audio_ad` break is served from.
    static let audioPlacement = "audio_between_tracks"

    /// The placement a `reel_video` break is served from.
    static let reelPlacement = "reel_between_tracks"

    /// The placement a break of `assetType` is asked for on.
    ///
    /// One placement per format, because the ads dashboard prices, caps, paces
    /// and schedules a slot, and a video and a soundtrack are not the same
    /// slot: a placement that accepted both could not be switched off, capped
    /// or priced for one without the other. `audio_between_tracks` accepts
    /// `audio_ad` only and `reel_between_tracks` accepts `reel_video` only.
    static func placement(for assetType: String) -> String {
        assetType == "reel_video" ? reelPlacement : audioPlacement
    }

    /// The format that goes first on the ask numbered `turn` — taken modulo the
    /// number of formats so a counter that only ever counts up can be handed
    /// straight in.
    static func assetType(atTurn turn: Int) -> String {
        assetTypes[((turn % assetTypes.count) + assetTypes.count) % assetTypes.count]
    }

    /// Whether `ad` is something an ad break can play, or a no-fill.
    ///
    /// The break needs a soundtrack (`audio_ad`) or a video (`reel_video`) to
    /// play, and nothing else: the picture it shows is optional. The server
    /// returns `squareImageUrl` / `wideImageUrl` only when the same campaign
    /// also has an image creative booked, so a plain audio ad has none of them.
    ///
    /// The format is checked as well as the URL, because the server answers
    /// with whatever the placement is set to accept: a placement edited to take
    /// `image_square` hands the break a PNG, which the break would pause the
    /// song for, fail to play, and drop within a second.
    static func isPlayable(_ ad: AdCreative?) -> Bool {
        guard let ad, let url = ad.assetUrl, !url.isEmpty else { return false }
        return assetTypes.contains(ad.assetType)
    }

    /// Why `ad`, which `isPlayable` turned away, never reached the screen.
    static func unplayableReason(_ ad: AdCreative) -> AdNotShownReason {
        guard let url = ad.assetUrl, !url.isEmpty else { return .assetMissing }
        return .unplayableFormat
    }

    /// Asks `serve` for an ad break by naming a format a break can play — never
    /// leaving the choice to the server — and returns the first that does, or
    /// nil.
    ///
    /// The server answers an unnamed ask with whatever the placement is set to
    /// accept, and a placement that also takes `image_square` hands back a PNG
    /// about as often as a soundtrack. A break cannot play it, and a song gets
    /// ONE chance at its boundary, so the ask must not be able to draw one: the
    /// server filters on the named format, and a format it does not accept or
    /// has nothing booked for is a plain no-fill.
    ///
    /// Each format is asked on its own placement, handed to `serve` along with
    /// the format so the two can never be paired wrongly. `start` picks which
    /// format goes first (taken modulo their count), so the caller can take
    /// turns between them; the other is tried when the first has nothing.
    ///
    /// A creative the server sends that a break cannot play is handed to
    /// `onUnplayable` before the next format is tried: it was served and will
    /// not be shown, which the server's counters only learn if the app says so.
    @MainActor
    static func serveBreak(
        start: Int = 0,
        serve: (_ placement: String, _ assetType: String) async -> AdCreative?,
        onUnplayable: (AdCreative) -> Void = { _ in }
    ) async -> AdCreative? {
        for offset in 0 ..< assetTypes.count {
            let format = assetType(atTurn: start + offset)
            let ad = await serve(placement(for: format), format)
            if isPlayable(ad) { return ad }
            if let ad { onUnplayable(ad) }
        }
        return nil
    }
}
