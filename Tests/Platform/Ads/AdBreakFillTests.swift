import Foundation
import Testing
@testable import Hallelujah

/// `AdBreakFill` — which format a break asks for, on which placement, and what
/// counts as playable. The Swift twin of `test/ads/ad_break_fill_test.dart`.
@MainActor
struct AdBreakFillTests {
    /// A served creative on `placement`, `assetUrl` overridable (`NSNull()` for none).
    private func served(
        assetType: String,
        placement: String = "audio_between_tracks",
        assetUrl: Any = "https://cdn.test/ad.mp4",
        token: String = "tok"
    ) -> AdCreative {
        makePlayerAdCreative(
            assetType: assetType,
            token: token,
            extra: ["placement": placement, "assetUrl": assetUrl]
        )
    }

    // MARK: placement per format

    // The ads dashboard prices, caps and switches a slot; a video and a
    // soundtrack are different slots, so each format has a placement of its own.

    @Test func aSoundtrackIsAskedForOnAudioBetweenTracks() {
        #expect(AdBreakFill.placement(for: "audio_ad") == "audio_between_tracks")
        #expect(AdBreakFill.audioPlacement == "audio_between_tracks")
    }

    @Test func aVideoIsAskedForOnReelBetweenTracks() {
        #expect(AdBreakFill.placement(for: "reel_video") == "reel_between_tracks")
        #expect(AdBreakFill.reelPlacement == "reel_between_tracks")
    }

    @Test func everyFormatABreakCanPlayHasAPlacementOfItsOwn() {
        let placements = Set(AdBreakFill.assetTypes.map(AdBreakFill.placement(for:)))
        #expect(placements.count == AdBreakFill.assetTypes.count)
    }

    @Test func theTurnPicksTheFormatAndWrapsAround() {
        #expect(AdBreakFill.assetType(atTurn: 0) == "audio_ad")
        #expect(AdBreakFill.assetType(atTurn: 1) == "reel_video")
        #expect(AdBreakFill.assetType(atTurn: 2) == "audio_ad")
        #expect(AdBreakFill.assetType(atTurn: 7) == "reel_video")
        #expect(AdBreakFill.placement(for: AdBreakFill.assetType(atTurn: 1)) == "reel_between_tracks")
    }

    @Test func aNegativeTurnStillLandsOnAFormat() {
        #expect(AdBreakFill.assetType(atTurn: -1) == "reel_video")
        #expect(AdBreakFill.assetType(atTurn: -2) == "audio_ad")
    }

    @Test func serveBreakPairsEachFormatWithItsOwnPlacement() async {
        var asked: [String] = []
        let ad = await AdBreakFill.serveBreak(serve: { placement, assetType in
            asked.append("\(placement)|\(assetType)")
            return nil
        })

        #expect(ad == nil)
        #expect(asked == ["audio_between_tracks|audio_ad", "reel_between_tracks|reel_video"])
    }

    @Test func aReelAskedFirstGoesToReelBetweenTracksAndStopsThere() async {
        var asked: [String] = []
        let ad = await AdBreakFill.serveBreak(start: 1, serve: { placement, assetType in
            asked.append("\(placement)|\(assetType)")
            return served(assetType: assetType, placement: placement)
        })

        #expect(asked == ["reel_between_tracks|reel_video"])
        #expect(ad?.placement == "reel_between_tracks")
    }

    @Test func theOtherFormatIsTriedWhenTheFirstHasNothing() async {
        let ad = await AdBreakFill.serveBreak(start: 0, serve: { placement, assetType in
            assetType == "audio_ad" ? nil : served(assetType: assetType, placement: placement)
        })

        #expect(ad?.assetType == "reel_video")
    }

    @Test func aReelAskedFirstFallsBackToTheSoundtrackOnItsOwnPlacement() async {
        var asked: [String] = []
        let ad = await AdBreakFill.serveBreak(start: 1, serve: { placement, assetType in
            asked.append("\(placement)|\(assetType)")
            return assetType == "reel_video" ? nil : served(assetType: assetType, placement: placement)
        })

        #expect(asked == ["reel_between_tracks|reel_video", "audio_between_tracks|audio_ad"])
        #expect(ad?.assetType == "audio_ad")
        #expect(ad?.placement == "audio_between_tracks")
    }

    // MARK: what a break can play

    @Test func onlyASoundtrackOrAVideoWithAUrlIsPlayable() {
        #expect(AdBreakFill.isPlayable(served(assetType: "audio_ad")))
        #expect(AdBreakFill.isPlayable(served(assetType: "reel_video")))
        #expect(!AdBreakFill.isPlayable(served(assetType: "image_square")))
        #expect(!AdBreakFill.isPlayable(served(assetType: "audio_ad", assetUrl: NSNull())))
        #expect(!AdBreakFill.isPlayable(served(assetType: "reel_video", assetUrl: "")))
        #expect(!AdBreakFill.isPlayable(nil))
    }

    // MARK: unplayable creatives are reported, not just dropped

    @Test func aPictureServedToABreakIsHandedToOnUnplayable() async {
        var dropped: [AdCreative] = []
        let ad = await AdBreakFill.serveBreak(
            serve: { _, _ in served(assetType: "image_square", assetUrl: "https://qa.test/ad.png") },
            onUnplayable: { dropped.append($0) }
        )

        #expect(ad == nil)
        // One per ask: both formats were tried and both answered with a picture.
        #expect(dropped.count == 2)
        #expect(dropped.first.map(AdBreakFill.unplayableReason) == .unplayableFormat)
    }

    @Test func aCreativeWithNoAssetIsReportedAsAMissingAsset() {
        #expect(AdBreakFill.unplayableReason(served(assetType: "audio_ad", assetUrl: NSNull())) == .assetMissing)
        #expect(AdBreakFill.unplayableReason(served(assetType: "audio_ad", assetUrl: "")) == .assetMissing)
    }

    @Test func aNoFillIsNotAnUnplayableCreative() async {
        var reported = 0
        _ = await AdBreakFill.serveBreak(serve: { _, _ in nil }, onUnplayable: { _ in reported += 1 })

        #expect(reported == 0) // nothing was served, so nothing was dropped
    }

    @Test func aPlayableCreativeIsNotReported() async {
        var reported = 0
        let ad = await AdBreakFill.serveBreak(
            serve: { placement, assetType in served(assetType: assetType, placement: placement) },
            onUnplayable: { _ in reported += 1 }
        )

        #expect(ad != nil)
        #expect(reported == 0)
    }

    @Test func aPictureFirstThenAVideoReportsThePictureAndPlaysTheVideo() async {
        var dropped = 0
        let ad = await AdBreakFill.serveBreak(
            start: 0,
            serve: { placement, assetType in
                assetType == "audio_ad"
                    ? served(assetType: "image_square", assetUrl: "https://qa.test/ad.png")
                    : served(assetType: assetType, placement: placement)
            },
            onUnplayable: { _ in dropped += 1 }
        )

        #expect(ad?.assetType == "reel_video")
        #expect(dropped == 1)
    }
}
