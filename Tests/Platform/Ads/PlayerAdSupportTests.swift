import Foundation
import Testing
@testable import Hallelujah

/// Fixture creative built the way the server's JSON builds it.
func makePlayerAdCreative(
    assetType: String = "image_square",
    token: String = "tok",
    headline: String? = nil,
    advertiser: String? = nil,
    extra: [String: Any] = [:]
) -> AdCreative {
    var json: [String: Any] = [
        "adId": "ad-\(token)",
        "campaignId": "camp",
        "placement": "player_image_square",
        "assetType": assetType,
        "assetUrl": "https://example.com/\(token).png",
        "impressionToken": token,
    ]
    if let headline { json["headline"] = headline }
    if let advertiser { json["advertiserName"] = advertiser }
    for (key, value) in extra { json[key] = value }
    return AdCreative.fromJSON(json)!
}

/// `AdTimeline.resolve`, `PlayerAdSurface`, `PlayerAdPacing`, `adBreakArtFor`.
struct PlayerAdSupportTests {
    @Test func timelineBlanksTakeTheBackendDefaults() {
        let timeline = AdTimeline.resolve(introSeconds: nil, displaySeconds: nil, gapSeconds: nil)
        #expect(timeline == AdTimeline(introSeconds: 3, displaySeconds: 30, gapSeconds: 5))
        #expect(timeline == AdTimeline())
    }

    @Test func timelineIsHeldToTheDashboardRange() {
        let low = AdTimeline.resolve(introSeconds: -4, displaySeconds: 0, gapSeconds: 0)
        #expect(low == AdTimeline(introSeconds: 0, displaySeconds: 5, gapSeconds: 1))
        let high = AdTimeline.resolve(introSeconds: 999, displaySeconds: 9_999, gapSeconds: 999)
        #expect(high == AdTimeline(introSeconds: 120, displaySeconds: 600, gapSeconds: 120))
    }

    @Test func surfaceFollowsTheCover() {
        #expect(PlayerAdSurface.forSongType("music") == .music)
        #expect(PlayerAdSurface.forSongType("episode") == .episode)
        #expect(PlayerAdSurface.forSongType(nil) == .episode)
        #expect(PlayerAdSurface.forCover(isEpisode: false) == .music)
        #expect(PlayerAdSurface.forCover(isEpisode: true) == .episode)
        #expect(PlayerAdSurface.music.placement == "player_image_square")
        #expect(PlayerAdSurface.music.assetType == "image_square")
        #expect(PlayerAdSurface.episode.placement == "player_image_wide_16_9")
        #expect(PlayerAdSurface.episode.assetType == "image_wide_16_9")
    }

    @MainActor
    @Test func pacingTakesOneSongInN() {
        let pacing = PlayerAdPacing()
        #expect(!pacing.takesOver("a", everyN: 3))
        #expect(!pacing.takesOver("b", everyN: 3))
        #expect(pacing.takesOver("c", everyN: 3))
        // Asked again about the same song: same answer, not counted twice.
        #expect(pacing.takesOver("c", everyN: 3))
        pacing.markDisplayed()
        #expect(!pacing.takesOver("d", everyN: 3))
    }

    @MainActor
    @Test func aDueSongWithNoAdStaysDue() {
        let pacing = PlayerAdPacing()
        #expect(pacing.takesOver("a", everyN: 1))
        // No `markDisplayed`: the next song is due straight away too.
        #expect(pacing.takesOver("b", everyN: 1))
    }

    @Test func breakArtPicksTheShapeOfTheCover() {
        let both = makePlayerAdCreative(extra: [
            "squareImageUrl": "https://example.com/sq.png",
            "wideImageUrl": "https://example.com/wide.png",
        ])
        #expect(adBreakArt(for: both, isMusic: true) == AdBreakArt(url: "https://example.com/sq.png", aspectRatio: 1))
        #expect(adBreakArt(for: both, isMusic: false) == AdBreakArt(url: "https://example.com/wide.png", aspectRatio: 16.0 / 9.0))
    }

    @Test func breakArtFallsBackToTheOtherPictureWhole() {
        let squareOnly = makePlayerAdCreative(extra: ["squareImageUrl": "https://example.com/sq.png"])
        #expect(adBreakArt(for: squareOnly, isMusic: false)?.aspectRatio == 1)
        let wideOnly = makePlayerAdCreative(extra: ["wideImageUrl": "https://example.com/wide.png"])
        #expect(adBreakArt(for: wideOnly, isMusic: true)?.aspectRatio == 16.0 / 9.0)
        #expect(adBreakArt(for: makePlayerAdCreative(), isMusic: true) == nil)
    }

    @Test func companionPictureIsTheSquareFirst() {
        let ad = makePlayerAdCreative(extra: [
            "companionImageUrl": "https://example.com/comp.png",
            "squareImageUrl": "https://example.com/sq.png",
        ])
        #expect(adBreakArt(for: ad, isMusic: true)?.url == "https://example.com/comp.png")
    }

    @Test func captionIsHeadlineOverAdvertiser() {
        let both = AdCaption(ad: makePlayerAdCreative(headline: " Big sale ", advertiser: "Acme"))
        #expect(both == AdCaption(title: "Big sale", subtitle: "Acme"))
        let nameOnly = AdCaption(ad: makePlayerAdCreative(headline: "  ", advertiser: "Acme"))
        #expect(nameOnly.title == "Acme")
        #expect(nameOnly.subtitle.isEmpty)
    }

    @Test func buttonOnlyWhenThereIsSomewhereToGo() {
        #expect(!makePlayerAdCreative().hasDestination)
        #expect(makePlayerAdCreative(extra: ["clickUrl": "https://example.com/c"]).hasDestination)
        #expect(makePlayerAdCreative().playerCTALabel == "Learn more")
        #expect(makePlayerAdCreative(extra: ["ctaLabel": " Shop now "]).playerCTALabel == "Shop now")
    }

    @Test func adLoadCarriesTheTimeline() {
        let load = AdLoad.fromJSON(["pacingEveryN": 4, "introSeconds": 1, "displaySeconds": 20, "gapSeconds": 2])
        #expect(load.pacingEveryN == 4)
        #expect(load.introSeconds == 1)
        #expect(load.displaySeconds == 20)
        #expect(load.gapSeconds == 2)
        #expect(AdLoad.fromJSON([:]).introSeconds == nil)
    }
}
