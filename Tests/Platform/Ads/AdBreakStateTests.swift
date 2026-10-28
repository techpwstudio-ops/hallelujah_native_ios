import CoreGraphics
import Foundation
import Testing
@testable import Hallelujah

/// `AdBreakProgress` and `AdPauseState` — the rules `AdPacingController` feeds
/// what the player reports. They decide what the server is told (an impression
/// is billed), so they are pinned here without a player.
struct AdBreakStateTests {
    private let audio = makePlayerAdCreative(assetType: "audio_ad", token: "audio")
    private let reel = makePlayerAdCreative(assetType: "reel_video", token: "reel")

    private func lingering(_ assetType: String = "audio_ad", companion: String? = "https://example.com/c.png") -> AdCreative {
        var extra: [String: Any] = ["lingerAfterDismiss": true]
        if let companion { extra["companionImageUrl"] = companion }
        return makePlayerAdCreative(assetType: assetType, token: "linger", extra: extra)
    }

    private let portrait = CGSize(width: 1080, height: 1920)

    /// The ratios, typed. Inside `#expect`, a `CGFloat` compared with a bare
    /// `1080.0 / 1920.0` came out unequal although both sides printed 0.5625; a
    /// `CGFloat` constant compares as it should.
    private let portraitRatio: CGFloat = 1080.0 / 1920.0
    private let landscapeRatio: CGFloat = 1920.0 / 1080.0

    /// Something the player can report about a reel, in any order.
    enum Event: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case ready, shape, seen
        var testDescription: String { rawValue }
    }

    private static let everyOrder: [[Event]] = [
        [.ready, .shape, .seen], [.ready, .seen, .shape], [.shape, .ready, .seen],
        [.shape, .seen, .ready], [.seen, .ready, .shape], [.seen, .shape, .ready],
    ]

    private func progress(after events: [Event]) -> AdBreakProgress {
        var progress = AdBreakProgress()
        for event in events {
            switch event {
            case .ready: progress.itemBecameReady()
            case .shape: progress.itemReportedSize(portrait)
            case .seen: progress.pictureWasSeen()
            }
        }
        return progress
    }

    // MARK: the format

    @Test func onlyAReelVideoIsAReel() {
        #expect(reel.isReel)
        #expect(!audio.isReel)
        #expect(!makePlayerAdCreative(assetType: "image_square").isReel)
    }

    // MARK: when the break is under way

    @Test func aNewBreakHasNothingToCount() {
        let progress = AdBreakProgress()
        #expect(!progress.itemIsReady)
        #expect(progress.videoAspectRatio == 0)
        #expect(!progress.isUnderway(audio))
        #expect(!progress.isUnderway(reel))
        #expect(!progress.shouldCountImpression(audio))
        #expect(!progress.shouldCountImpression(reel))
    }

    @Test func anAudioAdIsUnderwayAsSoonAsItCanPlay() {
        var progress = AdBreakProgress()
        progress.itemBecameReady()
        #expect(progress.isUnderway(audio))
    }

    @Test func aReelIsNotUnderwayUntilItHasAShape() {
        var progress = AdBreakProgress()
        progress.itemBecameReady()
        #expect(!progress.isUnderway(reel))

        progress.itemReportedSize(portrait)
        #expect(progress.isUnderway(reel))
    }

    @Test func aShapeWithoutAPlayableItemIsNotUnderway() {
        var progress = AdBreakProgress()
        progress.itemReportedSize(portrait)
        #expect(!progress.isUnderway(reel))
    }

    // MARK: the video's shape

    @Test func theAspectRatioIsWidthOverHeight() {
        var progress = AdBreakProgress()
        progress.itemReportedSize(portrait)
        #expect(progress.videoAspectRatio == portraitRatio)

        progress.itemReportedSize(CGSize(width: 1920, height: 1080))
        #expect(progress.videoAspectRatio == landscapeRatio)
    }

    @Test(arguments: [CGSize.zero, CGSize(width: 0, height: 1920), CGSize(width: 1080, height: 0), CGSize(width: -1080, height: 1920)])
    func aSizeThatIsNotAShapeIsIgnored(size: CGSize) {
        var progress = AdBreakProgress()
        progress.itemReportedSize(size)
        #expect(progress.videoAspectRatio == 0)

        // Nor does one take back a shape the item has already reported.
        progress.itemReportedSize(portrait)
        progress.itemReportedSize(size)
        #expect(progress.videoAspectRatio == portraitRatio)
    }

    // MARK: when the impression counts

    @Test func anAudioAdCountsTheMomentItCanPlay() {
        var progress = AdBreakProgress()
        #expect(!progress.shouldCountImpression(audio))

        progress.itemBecameReady()
        #expect(progress.shouldCountImpression(audio))
    }

    @Test func anAudioAdNeverWaitsForAPicture() {
        var progress = AdBreakProgress()
        progress.itemBecameReady()
        #expect(!progress.pictureSeen)
        #expect(progress.shouldCountImpression(audio))
    }

    @Test func aReelPlayingUnseenIsNotCounted() {
        var progress = AdBreakProgress()
        progress.itemBecameReady()
        progress.itemReportedSize(portrait)
        #expect(!progress.shouldCountImpression(reel))
    }

    @Test func aReelSeenButNotYetPlayableIsNotCounted() {
        var progress = AdBreakProgress()
        progress.pictureWasSeen()
        #expect(!progress.shouldCountImpression(reel))

        progress.itemBecameReady()
        #expect(!progress.shouldCountImpression(reel)) // still no shape
    }

    /// The picture can be on screen before the item has said it can play, or the
    /// other way round: all that matters is that all three have happened.
    @Test(arguments: AdBreakStateTests.everyOrder)
    func aReelCountsOnceItIsReadyShapedAndSeenInAnyOrder(events: [Event]) {
        #expect(progress(after: events).shouldCountImpression(reel))

        for missing in Event.allCases {
            let without = events.filter { $0 != missing }
            #expect(!progress(after: without).shouldCountImpression(reel), "without \(missing.rawValue)")
        }
    }

    @Test func anImpressionIsCountedOncePerBreak() {
        var audioProgress = AdBreakProgress()
        audioProgress.itemBecameReady()
        #expect(audioProgress.shouldCountImpression(audio))
        audioProgress.impressionWasSent()
        #expect(audioProgress.impressionCounted)
        #expect(!audioProgress.shouldCountImpression(audio))

        var reelProgress = progress(after: [.ready, .shape, .seen])
        reelProgress.impressionWasSent()
        #expect(!reelProgress.shouldCountImpression(reel))
    }

    // MARK: what a break that will not play says

    @Test func anAudioAdThatFailedIsReportedAsNotPreloaded() {
        #expect(AdBreakProgress().notShownReason(afterFailureOf: audio) == .preloadFailed)
    }

    @Test func aReelThatFailedIsReportedAsAVideoThatWouldNotStart() {
        #expect(AdBreakProgress().notShownReason(afterFailureOf: reel) == .videoInitFailed)
    }

    @Test func aFailureAfterTheImpressionCountedReportsNothing() {
        // It was shown, so "not shown" would be the other story for the same token.
        var audioProgress = AdBreakProgress()
        audioProgress.itemBecameReady()
        audioProgress.impressionWasSent()
        #expect(audioProgress.notShownReason(afterFailureOf: audio) == nil)

        var reelProgress = progress(after: [.ready, .shape, .seen])
        reelProgress.impressionWasSent()
        #expect(reelProgress.notShownReason(afterFailureOf: reel) == nil)
    }

    @Test func aReelThatWasReadyButNeverSeenIsStillReportedWhenItFails() {
        // Unseen means uncounted, so the only story left to tell is the failure.
        #expect(progress(after: [.ready, .shape]).notShownReason(afterFailureOf: reel) == .videoInitFailed)
    }

    // MARK: what stays up after the break

    @Test func aShownAdThatAskedToLingerLeavesItsCompanion() {
        var progress = AdBreakProgress()
        progress.itemBecameReady()
        progress.impressionWasSent()
        #expect(progress.leavesCompanion(lingering()))
    }

    @Test func anAdThatWasNeverShownLeavesNothing() {
        var progress = AdBreakProgress()
        progress.itemBecameReady()
        #expect(!progress.leavesCompanion(lingering()))
    }

    @Test func aShownAdThatDidNotAskToLingerLeavesNothing() {
        var progress = AdBreakProgress()
        progress.impressionWasSent()
        let notLingering = makePlayerAdCreative(
            assetType: "audio_ad",
            extra: ["companionImageUrl": "https://example.com/c.png"]
        )
        #expect(!progress.leavesCompanion(notLingering))
    }

    @Test func aLingeringAdWithNoCompanionPictureLeavesNothing() {
        var progress = AdBreakProgress()
        progress.impressionWasSent()
        #expect(!progress.leavesCompanion(lingering(companion: nil)))
    }

    // MARK: whose pause it is

    @Test func aBreakStartsPlaying() {
        let pause = AdPauseState()
        #expect(!pause.isPaused)
        #expect(!pause.isBySystem)
    }

    @Test func aStopTheListenerDidNotMakeReadsAsASystemPause() {
        var pause = AdPauseState()
        pause.playerStopped(itemFinished: false)
        #expect(pause.isPaused)
        #expect(pause.isBySystem)
    }

    @Test func aFinishedItemStoppingIsTheEndOfTheAdNotAPause() {
        var pause = AdPauseState()
        pause.playerStopped(itemFinished: true)
        #expect(!pause.isPaused)
        #expect(!pause.isBySystem)
    }

    @Test func thePlayerStartingTakesBackASystemPause() {
        var pause = AdPauseState()
        pause.playerStopped(itemFinished: false)
        pause.playerStarted()
        #expect(!pause.isPaused)
        #expect(!pause.isBySystem)
    }

    @Test func thePlayerStartingWhilePlayingChangesNothing() {
        var pause = AdPauseState()
        pause.playerStarted()
        #expect(pause == AdPauseState())
    }

    @Test func theListenersPauseIsTheirsToUndo() {
        var pause = AdPauseState()
        let pausedByTap = pause.listenerToggled()
        #expect(pausedByTap)
        #expect(pause.isPaused)
        #expect(!pause.isBySystem)

        // The player reporting a stop and then a start leaves their pause alone.
        pause.playerStopped(itemFinished: false)
        #expect(!pause.isBySystem)
        pause.playerStarted()
        #expect(pause.isPaused)
        #expect(!pause.isBySystem)

        let pausedBySecondTap = pause.listenerToggled()
        #expect(!pausedBySecondTap)
        #expect(!pause.isPaused)
    }

    @Test func aTapOnASystemPausedAdTakesItOverAndResumesIt() {
        var pause = AdPauseState()
        pause.playerStopped(itemFinished: false)

        let pausedByTap = pause.listenerToggled()
        #expect(!pausedByTap) // paused → playing: the tap resumes it
        #expect(!pause.isPaused)
        #expect(!pause.isBySystem)
    }

    @Test func anEndedInterruptionResumesASystemPauseWhenIOSAllowsIt() {
        var pause = AdPauseState()
        pause.playerStopped(itemFinished: false)

        let shouldStart = pause.interruptionEnded(shouldResume: true)
        #expect(shouldStart)
        #expect(!pause.isPaused)
        #expect(!pause.isBySystem)
    }

    @Test func anEndedInterruptionLeavesASystemPauseWhenIOSDoesNotAllowResuming() {
        var pause = AdPauseState()
        pause.playerStopped(itemFinished: false)

        let shouldStart = pause.interruptionEnded(shouldResume: false)
        #expect(!shouldStart)
        #expect(pause.isPaused)
        #expect(pause.isBySystem)
    }

    @Test func anEndedInterruptionNeverResumesAPauseTheListenerMade() {
        var pause = AdPauseState()
        _ = pause.listenerToggled()

        let shouldStart = pause.interruptionEnded(shouldResume: true)
        #expect(!shouldStart)
        #expect(pause.isPaused)
    }

    @Test func anEndedInterruptionWhilePlayingChangesNothing() {
        var pause = AdPauseState()
        let shouldStart = pause.interruptionEnded(shouldResume: true)
        #expect(!shouldStart)
        #expect(pause == AdPauseState())
    }
}
