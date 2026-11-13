import Foundation
import Testing
@testable import Hallelujah

/// A quality change on an episode's silent video, YouTube style: the picture on screen keeps playing
/// while the new file opens behind it, and the two swap only once the new one is in step with the
/// audio and has faded in. The cover never shows in between.
@MainActor
struct PlayerVideoStageTests {
    private typealias Stage = PlayerVideoStage<FakeVideoPlayback>

    private let low = URL(string: "https://cdn.example/ep1/480.mp4")!
    private let high = URL(string: "https://cdn.example/ep1/720.mp4")!
    private let highest = URL(string: "https://cdn.example/ep1/1080.mp4")!

    /// The layer's loop runs this quick while a switch is under way.
    private let step = VideoSync.fastReconcileIntervalMs
    private let fadeMs = 220

    /// The audio playing a minute in, and players that follow it, with fake time.
    @MainActor
    private final class Rig {
        let clock = FakeAudioClock()
        private var playbacks: [FakeVideoPlayback] = []

        init() {
            clock.positionMs = 60_000
            clock.isPlaying = true
        }

        /// A player for `url`, playing in step with the audio. `ready: false` is one still opening.
        func player(_ url: URL, ready: Bool = true) -> Stage.Player {
            let playback = FakeVideoPlayback()
            playback.isReady = ready
            playback.positionMs = clock.positionMs
            playback.isPlaying = true
            playbacks.append(playback)
            let controller = PlayerVideoController(clock: clock, songId: "ep1")
            controller.attach(playback)
            return .init(controller: controller, playback: playback, url: url)
        }

        /// A player on screen: in step and shown, as a running layer has it.
        func showing(_ url: URL) -> Stage.Player {
            let shown = player(url)
            shown.controller.tick()
            return shown
        }

        /// `ms` of real time, then one look, as the layer's loop does.
        func tick(_ stage: Stage, ms: Int) -> Stage.Event? {
            clock.advance(byMs: ms)
            for playback in playbacks { playback.advance(byMs: ms) }
            return stage.tick(stepMs: ms)
        }
    }

    private func switched(_ event: Stage.Event?) -> Stage.Player? {
        if case .switched(let player) = event { return player }
        return nil
    }

    private func failed(_ event: Stage.Event?) -> Bool {
        if case .failed = event { return true }
        return false
    }

    // MARK: First file

    @Test func theFirstFileGoesStraightOnScreen() {
        let rig = Rig()
        let stage = Stage(wanted: high)
        #expect(stage.needsOpening)

        let first = rig.player(high)
        #expect(stage.open(first) == .current)

        #expect(stage.current?.controller === first.controller)
        #expect(!stage.needsOpening)
        #expect(stage.isSettled)
    }

    // MARK: Switching quality

    @Test func theOldPictureStaysUpUntilTheNewOneIsInStepAndFadedIn() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old, fadeMs: fadeMs)
        #expect(stage.isPictureShown)

        stage.want(high)
        #expect(stage.needsOpening)
        let new = rig.player(high, ready: false)
        #expect(stage.open(new) == .incoming)
        #expect(!stage.needsOpening, "opening already")

        // The new file takes a second to open: the old picture plays on.
        for _ in 0..<20 {
            #expect(rig.tick(stage, ms: step) == nil)
            #expect(stage.isPictureShown)
            #expect(stage.current?.controller === old.controller)
        }
        #expect(old.playback.teardowns == 0)

        // Ready now. It catches up with the audio and fades in over the old picture.
        new.playback.isReady = true
        var elapsedSinceShown: Int?
        var swap: Stage.Player?
        for _ in 0..<40 where swap == nil {
            let event = rig.tick(stage, ms: step)
            swap = switched(event)
            #expect(stage.isPictureShown, "never the cover")
            if swap == nil {
                #expect(old.playback.teardowns == 0, "the old picture stays under the fade")
                if new.controller.isShown { elapsedSinceShown = (elapsedSinceShown.map { $0 + step }) ?? 0 }
            }
        }

        #expect(swap?.controller === new.controller)
        #expect((elapsedSinceShown ?? 0) + step >= fadeMs, "the fade had time to finish")
        #expect(stage.current?.controller === new.controller)
        #expect(stage.incoming == nil)
        #expect(stage.isSettled)
        #expect(old.playback.teardowns == 1, "released once, after the swap")
        #expect(new.playback.teardowns == 0)
    }

    @Test func theSwapComesOneFadeAfterTheNewPictureIsInStep() {
        let rig = Rig()
        let stage = Stage(wanted: low, showing: rig.showing(low), fadeMs: fadeMs)
        stage.want(high)
        let new = rig.player(high)
        stage.open(new)

        // In step on its first look: the fade starts here.
        #expect(rig.tick(stage, ms: step) == nil)
        #expect(new.controller.isShown)

        var ticks = 0
        var swap: Stage.Player?
        while swap == nil, ticks < 20 {
            swap = switched(rig.tick(stage, ms: step))
            ticks += 1
        }
        #expect(swap?.controller === new.controller)
        #expect(ticks * step >= fadeMs)
        #expect((ticks - 1) * step < fadeMs, "and not a tick later than it needs")
    }

    @Test func aNewQualityThatCannotPlayIsReportedAndTheOldPictureIsLeftAlone() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old)
        stage.want(high)
        let new = rig.player(high, ready: false)
        stage.open(new)

        new.playback.hasFailed = true

        #expect(failed(rig.tick(stage, ms: step)))
        #expect(stage.incoming == nil)
        #expect(new.playback.teardowns == 1)
        #expect(stage.current?.controller === old.controller)
        #expect(old.playback.teardowns == 0)
    }

    @Test func aBrokenPictureMakesWayAtOnce() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old)
        stage.want(high)
        let new = rig.player(high, ready: false)
        stage.open(new)

        old.playback.hasFailed = true

        #expect(switched(rig.tick(stage, ms: step))?.controller === new.controller)
        #expect(stage.current?.controller === new.controller)
        #expect(!stage.hasFailed, "the new file is still on its way")
    }

    @Test func aFileOpenedAfterThePictureFailedGoesStraightOnScreen() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old)
        old.playback.hasFailed = true
        #expect(failed(rig.tick(stage, ms: step)))
        #expect(stage.hasFailed)

        stage.want(high)
        let new = rig.player(high)
        #expect(stage.open(new) == .current)
        #expect(stage.incoming == nil)
    }

    // MARK: Picking again

    @Test func pickingAgainBeforeTheSwitchLetsTheHalfOpenedFileGo() {
        let rig = Rig()
        let stage = Stage(wanted: low, showing: rig.showing(low))
        stage.want(high)
        let half = rig.player(high, ready: false)
        stage.open(half)

        stage.want(highest)

        #expect(half.playback.teardowns == 1)
        #expect(stage.incoming == nil)
        #expect(stage.needsOpening)
        let next = rig.player(highest, ready: false)
        #expect(stage.open(next) == .incoming)
        #expect(stage.incoming?.controller === next.controller)
    }

    @Test func pickingTheQualityOnScreenAgainCancelsTheSwitch() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old)
        stage.want(high)
        let half = rig.player(high, ready: false)
        stage.open(half)

        stage.want(low)

        #expect(half.playback.teardowns == 1)
        #expect(!stage.needsOpening)
        #expect(stage.isSettled)
        #expect(stage.current?.controller === old.controller)
        #expect(old.playback.teardowns == 0)
    }

    @Test func aLayerThatTakesOverAnotherQualityKeepsItUpWhileOpeningItsOwn() {
        // The pager rebuilt the page mid-switch: the new layer gets the old quality's player.
        let rig = Rig()
        let held = rig.showing(low)
        let stage = Stage(wanted: high, showing: held)

        #expect(stage.isPictureShown, "the first frame draws the picture, not the cover")
        #expect(stage.needsOpening, "and the quality the listener picked still opens")
    }

    // MARK: Letting go

    @Test func droppingTheFileOpeningReleasesItAndNotThePicture() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old)
        stage.want(high)
        let new = rig.player(high, ready: false)
        stage.open(new)

        stage.drop(old)
        #expect(old.playback.teardowns == 0, "the picture on screen is the handoff's to let go")

        stage.drop(new)
        stage.drop(new)
        #expect(new.playback.teardowns == 1)
        #expect(stage.incoming == nil)
    }

    @Test func goingOutOfSightReleasesBoth() {
        let rig = Rig()
        let old = rig.showing(low)
        let stage = Stage(wanted: low, showing: old)
        stage.want(high)
        let new = rig.player(high, ready: false)
        stage.open(new)

        stage.clear()

        #expect(old.playback.teardowns == 1)
        #expect(new.playback.teardowns == 1)
        #expect(stage.current == nil)
        #expect(stage.incoming == nil)
        #expect(stage.needsOpening, "coming back opens the file again")
    }

    @Test func nothingHeldClearsAStalePicture() {
        let rig = Rig()
        let stage = Stage(wanted: low, showing: rig.showing(low))

        stage.show(nil)

        #expect(stage.current == nil)
        #expect(stage.needsOpening)
    }
}
