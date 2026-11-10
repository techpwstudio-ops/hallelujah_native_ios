import CoreGraphics
import Testing
@testable import Hallelujah

/// The silent video's controller against a fake clock and a fake playback, with fake time: seconds
/// of playback run in an instant, and every scenario of the sync contract is a plain test.
@MainActor
struct PlayerVideoControllerTests {
    /// A controller, a fake clock and a fake playback. `tick(_:)` advances both fakes by one period
    /// and then lets the controller look, the way the layer's loop does.
    @MainActor
    private final class Rig {
        let clock = FakeAudioClock()
        var playback = FakeVideoPlayback()
        let controller: PlayerVideoController

        init(songId: String = "ep1") {
            controller = PlayerVideoController(clock: clock, songId: songId)
            controller.attach(playback)
        }

        /// The audio is playing at `audioMs` and the video is parked at `videoMs`.
        func start(audioMs: Int, videoMs: Int) {
            clock.positionMs = audioMs
            clock.isPlaying = true
            playback.positionMs = videoMs
        }

        /// The first look: no time passes.
        func look() {
            controller.tick()
        }

        func tick(_ count: Int = 1) {
            for _ in 0..<count {
                clock.advance(byMs: VideoSync.reconcileIntervalMs)
                playback.advance(byMs: VideoSync.reconcileIntervalMs)
                controller.tick()
            }
        }

        func attach(_ next: FakeVideoPlayback) {
            playback = next
            controller.attach(next)
        }
    }

    // MARK: 1. Catch-up

    @Test func aVideoFarBehindIsJumpedOnceAndThenFollows() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 0)

        rig.look()
        #expect(rig.playback.seeks == [5_200])
        #expect(rig.playback.plays == 1)
        #expect(!rig.controller.isShown, "the video was far out on the first look")

        rig.tick()
        #expect(rig.controller.isShown)

        rig.tick(20)
        #expect(rig.playback.seeks.count == 1)
        #expect(rig.playback.plays == 1)
        #expect(rig.controller.isShown)
    }

    // MARK: 2. Already in step

    @Test func aVideoAlreadyInStepIsNotJumpedAndShowsAtOnce() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 5_000)

        rig.look()
        #expect(rig.playback.seeks.isEmpty)
        #expect(rig.playback.plays == 1)
        #expect(rig.controller.isShown)
    }

    // MARK: 3. Pause, resume, scrub

    @Test func pauseResumeAndScrubFollowTheAudio() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 5_000)
        rig.look()
        rig.tick(8)
        #expect(rig.controller.isShown)

        rig.clock.isPlaying = false
        rig.tick()
        #expect(rig.playback.pauses == 1)
        #expect(!rig.playback.isPlaying)

        rig.tick(4)
        rig.clock.positionMs = 20_000
        rig.tick()
        #expect(rig.playback.seeks.last == 20_000)
        #expect(rig.playback.plays == 1)

        rig.clock.isPlaying = true
        rig.tick()
        #expect(rig.playback.plays == 2)
        #expect(rig.controller.isShown)
    }

    // MARK: 4. Pause after a catch-up

    @Test func pausingAfterACatchUpPutsTheVideoExactlyOnTheAudio() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 0)
        rig.look()
        rig.tick(8)

        rig.clock.isPlaying = false
        rig.tick()
        // The video had been a lead ahead of the audio; paused, it is put exactly on it.
        #expect(rig.playback.seeks.last == rig.clock.positionMs)
        #expect(rig.playback.pauses == 1)
    }

    // MARK: 5. A frozen video

    @Test func aFrozenVideoIsRetriedAfterTheCooldownAndThenGivenUpOnForTheCover() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 5_000)
        rig.look()
        rig.playback.frozen = true
        rig.playback.ignoresSeeks = true

        rig.tick(10)
        #expect(rig.controller.isShown, "2.5 s in, the drift has not been past the limit for the grace yet")

        rig.tick()
        #expect(!rig.controller.isShown, "2.75 s in, it has")
        // At 0.5 s, and again once the cooldown was up (2.0 s), never in between.
        #expect(rig.playback.seeks.count == 2)
    }

    // MARK: 6. The audio jumps 3 s

    @Test func theCoverReturnsOnlyAfterTheGraceWhenTheAudioLeapsAhead() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 5_000)
        rig.look()
        rig.tick(2)
        rig.playback.ignoresSeeks = true
        rig.clock.positionMs += 3_000

        var shownAfter: [Bool] = []
        for _ in 0..<5 {
            rig.tick()
            shownAfter.append(rig.controller.isShown)
        }
        #expect(shownAfter == [true, true, true, true, false])
    }

    // MARK: 7. The cooldown

    @Test func theSecondJumpWaitsForTheCooldown() {
        let rig = Rig()
        rig.start(audioMs: 50_000, videoMs: 0)
        rig.playback.ignoresSeeks = true
        rig.look()
        #expect(rig.playback.seeks.count == 1)

        var jumpTicks: [Int] = []
        for tick in 1...8 {
            let before = rig.playback.seeks.count
            rig.tick()
            if rig.playback.seeks.count > before { jumpTicks.append(tick) }
        }
        #expect(jumpTicks == [6])
    }

    // MARK: 8. A slow jump

    @Test func aJumpInFlightIsNotRepeatedAndTheCoverStaysDown() {
        let rig = Rig()
        rig.playback.seekLatencyMs = 1_000
        rig.start(audioMs: 5_000, videoMs: 0)

        rig.look()
        rig.tick(3)
        #expect(rig.playback.seeks.count == 1)
        #expect(!rig.controller.isShown)
    }

    // MARK: 9. Another episode's audio

    @Test func audioOfAnotherEpisodeIsNotFollowed() {
        let rig = Rig()
        rig.clock.mediaId = "other"
        rig.start(audioMs: 5_000, videoMs: 0)

        rig.look()
        rig.tick(8)
        #expect(rig.playback.seeks.isEmpty)
        #expect(rig.playback.plays == 0)
        #expect(!rig.controller.isShown)

        rig.clock.mediaId = "ep1"
        rig.tick()
        #expect(rig.playback.seeks.count == 1)
        #expect(rig.playback.plays == 1)
    }

    // MARK: 10. Audio not ready while the video plays

    @Test func anAudioThatStopsBeingReadyPausesTheVideoOnceAndKeepsThePicture() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 5_000)
        rig.look()
        rig.tick(4)
        #expect(rig.controller.isShown)

        rig.clock.isReady = false
        rig.tick(3)
        #expect(rig.playback.pauses == 1)
        #expect(rig.playback.seeks.isEmpty)
        #expect(rig.controller.isShown)

        rig.clock.isReady = true
        rig.tick()
        #expect(rig.playback.plays == 2)
    }

    // MARK: 11. A playback that is not ready yet

    @Test func aPlaybackStillOpeningGetsNoCommandsAndNoTimeCounted() {
        let rig = Rig()
        rig.playback.isReady = false
        rig.start(audioMs: 5_000, videoMs: 0)

        rig.look()
        rig.tick(4)
        #expect(rig.playback.seeks.isEmpty)
        #expect(rig.playback.plays == 0)
        #expect(rig.playback.pauses == 0)

        rig.playback.isReady = true
        rig.look()
        #expect(rig.playback.seeks.count == 1)

        rig.tick(5)
        #expect(rig.playback.seeks.count == 1)
    }

    // MARK: 12. Failure

    @Test func aFailedPlaybackIsTornDownOnceAndReported() {
        let rig = Rig()
        rig.start(audioMs: 5_000, videoMs: 5_000)
        rig.look()
        rig.tick(2)
        #expect(!rig.controller.hasFailed)

        rig.playback.hasFailed = true
        rig.tick()
        #expect(rig.controller.hasFailed)
        #expect(rig.playback.teardowns == 1)
        #expect(!rig.controller.isShown)

        rig.tick(4)
        #expect(rig.playback.teardowns == 1)
        #expect(rig.controller.hasFailed)

        rig.attach(FakeVideoPlayback())
        #expect(!rig.controller.hasFailed)
    }

    // MARK: 13. Release and attach

    @Test func releaseIsSafeToRepeatAndOnlyTheNewPlayerIsDriven() {
        let rig = Rig()
        let first = rig.playback
        rig.start(audioMs: 5_000, videoMs: 0)
        rig.look()
        #expect(first.seeks == [5_200])

        rig.controller.release()
        rig.controller.release()
        #expect(first.teardowns == 1)
        #expect(!rig.controller.isShown)

        rig.tick(2)
        #expect(first.seeks == [5_200], "a released controller neither reads nor commands")

        let a = FakeVideoPlayback()
        let b = FakeVideoPlayback()
        rig.attach(a)
        rig.attach(b)
        #expect(a.teardowns == 1)

        rig.clock.positionMs = 9_000
        rig.controller.tick()
        #expect(a.seeks.isEmpty)
        #expect(!b.seeks.isEmpty)
    }

    // MARK: Extra: what the view reads

    @Test func theControllerPublishesThePictureSizeAndClearsItOnRelease() {
        let rig = Rig()
        rig.playback.videoSize = CGSize(width: 1_920, height: 1_080)
        rig.start(audioMs: 5_000, videoMs: 5_000)
        #expect(rig.controller.videoSize == .zero)

        rig.look()
        #expect(rig.controller.videoSize == CGSize(width: 1_920, height: 1_080))

        rig.controller.release()
        #expect(rig.controller.videoSize == .zero)
    }

    @Test func releaseLeavesAFailureForTheViewToReport() {
        let rig = Rig()
        rig.playback.hasFailed = true
        rig.look()
        #expect(rig.controller.hasFailed)

        rig.controller.release()
        #expect(rig.controller.hasFailed)
    }

    @Test func aControllerNeverCommandsTheAudioClock() {
        // The type of `AudioClock` has four reads and no methods, so this is a compile-time guarantee;
        // this test only pins that the fake carries no command a controller could have used.
        let clock = FakeAudioClock()
        clock.isPlaying = true
        clock.positionMs = 5_000
        let controller = PlayerVideoController(clock: clock, songId: "ep1")
        controller.attach(FakeVideoPlayback())
        for _ in 0..<5 { controller.tick() }
        #expect(clock.positionMs == 5_000)
        #expect(clock.isPlaying)
    }
}
