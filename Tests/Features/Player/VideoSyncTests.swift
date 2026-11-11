import Testing
@testable import Hallelujah

/// The planner is pure, so every rule of the silent video's sync is a plain table here.
/// Defaults unless a test says otherwise: audio ready and playing at 10,000; video playing at
/// 10,000, not buffering, 30 minutes long; no previous seek.
struct VideoSyncTests {
    // MARK: Helpers

    private func audio(_ positionMs: Int = 10_000, ready: Bool = true, playing: Bool = true) -> AudioReading {
        AudioReading(positionMs: positionMs, isReady: ready, isPlaying: playing)
    }

    private func video(
        _ positionMs: Int = 10_000,
        duration: Int = 1_800_000,
        playing: Bool = true,
        buffering: Bool = false
    ) -> VideoReading {
        VideoReading(positionMs: positionMs, durationMs: duration, isPlaying: playing, isBuffering: buffering)
    }

    private func plan(_ audio: AudioReading, _ video: VideoReading, since: Int? = nil) -> VideoSyncPlan {
        VideoSync.plan(audio: audio, video: video, sinceLastSeekMs: since)
    }

    private func shown(
        was: Bool = false,
        _ audio: AudioReading,
        _ video: VideoReading,
        outOfSyncFor: Int = 0
    ) -> Bool {
        VideoSync.nextShown(shown: was, audio: audio, video: video, outOfSyncForMs: outOfSyncFor)
    }

    // MARK: Constants

    @Test func theConstantsAreTheOnesTheFlutterAppUses() {
        #expect(VideoSync.playingToleranceMs == 300)
        #expect(VideoSync.pausedToleranceMs == 120)
        #expect(VideoSync.playingSeekCooldownMs == 1_500)
        #expect(VideoSync.pausedSeekCooldownMs == 250)
        #expect(VideoSync.seekLeadMs == 200)
        #expect(VideoSync.tailGuardMs == 150)
        #expect(VideoSync.hideDriftMs == 1_500)
        #expect(VideoSync.hideGraceMs == 1_000)
        #expect(VideoSync.reconcileIntervalMs == 250)
        #expect(VideoSync.fastReconcileIntervalMs < VideoSync.reconcileIntervalMs)
        #expect(VideoSync.spinnerDelayMs == 1_000)
    }

    @Test func theLeadStaysBelowThePlayingTolerance() {
        // A jump lands this far ahead; if that were past the tolerance the next look would jump back.
        #expect(VideoSync.seekLeadMs < VideoSync.playingToleranceMs)
    }

    // MARK: plan: the audio is not ready

    @Test func anAudioThatIsNotReadyPausesAPlayingVideo() {
        #expect(plan(audio(ready: false), video(playing: true)) == VideoSyncPlan(seekToMs: nil, play: false))
    }

    @Test func anAudioThatIsNotReadyLeavesAPausedVideoAlone() {
        #expect(plan(audio(ready: false), video(playing: false)).isNoop)
    }

    @Test func anAudioThatIsNotReadyNeverJumpsTheVideo() {
        #expect(plan(audio(ready: false), video(0, playing: false)).seekToMs == nil)
    }

    // MARK: plan: both running

    @Test(arguments: [10_300, 9_700])
    func driftOfExactlyTheToleranceIsInStep(videoMs: Int) {
        #expect(plan(audio(), video(videoMs)).isNoop)
    }

    @Test(arguments: [10_301, 9_699])
    func driftPastTheToleranceJumpsAheadOfTheAudio(videoMs: Int) {
        #expect(plan(audio(), video(videoMs)) == VideoSyncPlan(seekToMs: 10_200, play: nil))
    }

    @Test func theCooldownHoldsASecondJumpBack() {
        #expect(plan(audio(), video(0), since: 1_499).seekToMs == nil)
        #expect(plan(audio(), video(0), since: 1_500).seekToMs == 10_200)
        #expect(plan(audio(), video(0), since: nil).seekToMs == 10_200)
    }

    @Test func aBufferingVideoIsNotJumpedWhilePlaying() {
        #expect(plan(audio(), video(0, playing: false, buffering: true)).isNoop)
    }

    @Test func aPausedVideoInStepIsToldToPlay() {
        #expect(plan(audio(), video(playing: false)) == VideoSyncPlan(seekToMs: nil, play: true))
    }

    @Test func aBufferingVideoInStepIsNotToldAgain() {
        #expect(plan(audio(), video(playing: false, buffering: true)).isNoop)
    }

    @Test func aPausedVideoFarBehindCatchesUpInOnePass() {
        #expect(plan(audio(), video(0, playing: false)) == VideoSyncPlan(seekToMs: 10_200, play: true))
    }

    // MARK: plan: the audio is paused

    @Test(arguments: [9_880, 10_120])
    func pausedDriftOfExactlyTheToleranceDoesNotJump(videoMs: Int) {
        #expect(plan(audio(playing: false), video(videoMs, playing: false)).seekToMs == nil)
    }

    @Test(arguments: [9_879, 10_121])
    func pausedDriftPastTheToleranceLandsExactlyOnTheAudio(videoMs: Int) {
        #expect(plan(audio(playing: false), video(videoMs, playing: false)).seekToMs == 10_000)
    }

    @Test func aPausedAudioPutsAFarVideoExactlyOnItsPosition() {
        #expect(plan(audio(playing: false), video(0, playing: false)) == VideoSyncPlan(seekToMs: 10_000, play: nil))
    }

    @Test func thePausedCooldownIsShort() {
        let paused = audio(playing: false)
        #expect(plan(paused, video(0, playing: false), since: 249).seekToMs == nil)
        #expect(plan(paused, video(0, playing: false), since: 250).seekToMs == 10_000)
    }

    @Test func aPausedAudioPausesAPlayingVideoThatIsInStep() {
        #expect(plan(audio(playing: false), video(playing: true)) == VideoSyncPlan(seekToMs: nil, play: false))
    }

    @Test func aPausedAudioStillJumpsABufferingVideoToTheFrame() {
        #expect(plan(audio(playing: false), video(0, playing: false, buffering: true)).seekToMs == 10_000)
    }

    // MARK: plan: the end of the video

    @Test func theVideoIsNotAskedToPlayWithinTheTailGuard() {
        func play(at audioMs: Int) -> Bool? {
            plan(audio(audioMs), video(audioMs, duration: 600_000, playing: false)).play
        }
        #expect(play(at: 599_849) == true)
        #expect(play(at: 599_850) == nil)
        #expect(play(at: 599_851) == nil)
    }

    @Test func aJumpWhilePlayingIsCappedByTheEnd() {
        func landing(at audioMs: Int) -> Int? {
            plan(audio(audioMs), video(0, duration: 600_000, playing: true)).seekToMs
        }
        #expect(landing(at: 599_600) == 599_800)
        #expect(landing(at: 599_840) == 599_850)
    }

    @Test func nearTheEndAVideoStillPlayingIsPausedAndPutOnTheAudio() {
        let result = plan(audio(599_900), video(599_700, duration: 600_000, playing: true))
        #expect(result == VideoSyncPlan(seekToMs: 599_900, play: false))
    }

    @Test func aShortVideoHoldsItsLastFrame() {
        let toLastFrame = plan(audio(90_000), video(0, duration: 60_000, playing: false))
        #expect(toLastFrame == VideoSyncPlan(seekToMs: 60_000, play: nil))
        #expect(plan(audio(90_000), video(60_000, duration: 60_000, playing: false)).isNoop)
    }

    @Test func anUnknownLengthIsNeverNearTheEnd() {
        let result = plan(audio(10_000), video(0, duration: 0, playing: false))
        #expect(result == VideoSyncPlan(seekToMs: 10_200, play: true))
    }

    // MARK: plan: what counts as a command

    @Test func anEmptyPlanIsANoop() {
        #expect(VideoSyncPlan().isNoop)
    }

    @Test func aPauseAndAJumpToZeroAreCommands() {
        #expect(!VideoSyncPlan(seekToMs: nil, play: false).isNoop)
        #expect(!VideoSyncPlan(seekToMs: 0, play: nil).isNoop)
    }

    // MARK: drift

    @Test func driftIsTheDistanceInEitherDirection() {
        #expect(VideoSync.drift(audio: audio(10_000), video: video(10_400)) == 400)
        #expect(VideoSync.drift(audio: audio(10_000), video: video(9_600)) == 400)
        #expect(VideoSync.drift(audio: audio(10_000), video: video(10_000)) == 0)
    }

    @Test func driftIsMeasuredToTheEndOfAShortVideo() {
        #expect(VideoSync.drift(audio: audio(90_000), video: video(60_000, duration: 60_000)) == 0)
        #expect(VideoSync.drift(audio: audio(90_000), video: video(0, duration: 60_000)) == 60_000)
    }

    @Test func driftHasNoEndToClampToWhenTheLengthIsUnknown() {
        #expect(VideoSync.drift(audio: audio(90_000), video: video(60_000, duration: 0)) == 30_000)
    }

    // MARK: nextShown

    @Test func anAudioThatIsNotReadyKeepsWhateverTheCoverIsDoing() {
        #expect(shown(was: true, audio(ready: false), video(0), outOfSyncFor: 60_000))
        #expect(!shown(was: false, audio(ready: false), video()))
    }

    @Test(arguments: [10_300, 9_700])
    func aVideoWithinTheToleranceComesUp(videoMs: Int) {
        #expect(shown(audio(), video(videoMs)))
    }

    @Test(arguments: [10_301, 9_699])
    func aVideoPastTheToleranceStaysDown(videoMs: Int) {
        #expect(!shown(audio(), video(videoMs)))
    }

    @Test(arguments: [10_120, 9_880])
    func whilePausedTheToleranceIsTighterAndHoldsAtItsEdge(videoMs: Int) {
        #expect(shown(audio(playing: false), video(videoMs)))
    }

    @Test(arguments: [10_121, 9_879])
    func whilePausedOnePastTheEdgeStaysDown(videoMs: Int) {
        #expect(!shown(audio(playing: false), video(videoMs)))
    }

    @Test func aBufferingVideoStaysDown() {
        #expect(!shown(audio(), video(buffering: true)))
    }

    @Test func nearTheEndThePausedToleranceApplies() {
        #expect(!shown(audio(599_900), video(599_700, duration: 600_000)))
    }

    @Test func midVideoTwoHundredOffIsFine() {
        #expect(shown(audio(500_000), video(499_800, duration: 600_000)))
    }

    @Test func aPauseDoesNotBringUpAVideoThatIsOut() {
        #expect(!shown(audio(playing: false), video(0)))
    }

    @Test func aPictureOnScreenSurvivesDriftUntilTheGraceIsUp() {
        #expect(shown(was: true, audio(), video(11_500), outOfSyncFor: 5_000))
        #expect(shown(was: true, audio(), video(11_501), outOfSyncFor: 999))
        #expect(!shown(was: true, audio(), video(11_501), outOfSyncFor: 1_000))
        #expect(!shown(was: true, audio(), video(8_499), outOfSyncFor: 1_000))
        #expect(shown(was: true, audio(), video(8_500), outOfSyncFor: 1_000))
    }

    @Test func aPictureOnScreenSurvivesBuffering() {
        #expect(shown(was: true, audio(), video(buffering: true)))
    }

    @Test func aShortVideoParkedOnItsLastFrameStaysUp() {
        let parked = video(60_000, duration: 60_000)
        #expect(shown(was: true, audio(90_000), parked, outOfSyncFor: 60_000))
        #expect(shown(was: false, audio(90_000), parked))
    }

    // MARK: fit

    @Test func aShapeWithinAFewPercentFillsTheBox() {
        #expect(VideoSync.fit(videoAspect: 1.05, boxAspect: 1) == .cover)
        #expect(VideoSync.fit(videoAspect: 0.95, boxAspect: 1) == .cover)
        #expect(VideoSync.fit(videoAspect: 16.0 / 9.0, boxAspect: 16.0 / 9.0) == .cover)
    }

    @Test func aDifferentShapeIsFitted() {
        #expect(VideoSync.fit(videoAspect: 1.07, boxAspect: 1) == .contain)
        #expect(VideoSync.fit(videoAspect: 0.93, boxAspect: 1) == .contain)
        #expect(VideoSync.fit(videoAspect: 16.0 / 9.0, boxAspect: 1) == .contain)
    }

    @Test func anUnknownOrNonsenseShapeIsFitted() {
        #expect(VideoSync.fit(videoAspect: 0, boxAspect: 1) == .contain)
        #expect(VideoSync.fit(videoAspect: -1, boxAspect: 1) == .contain)
        #expect(VideoSync.fit(videoAspect: 1, boxAspect: 0) == .contain)
        #expect(VideoSync.fit(videoAspect: 1, boxAspect: -1) == .contain)
    }
}
