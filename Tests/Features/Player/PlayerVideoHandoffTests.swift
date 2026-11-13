import Foundation
import Testing
@testable import Hallelujah

/// The handoff of an open silent video from a layer that goes away to a new layer for the same
/// episode. Shuffle moves the playing episode to another page of the artwork pager, which builds
/// that page afresh; the player must carry over, not be torn down and opened again.
@MainActor
struct PlayerVideoHandoffTests {
    private let key = "ep1"
    private let otherEpisode = "ep2"
    private let file = URL(string: "https://cdn.example/ep1/720.mp4")!

    /// A handoff whose grace period ends as soon as anything awaits `settle()`.
    private func makeHandoff() -> PlayerVideoHandoff<FakeVideoPlayback> {
        PlayerVideoHandoff(graceMs: 1_000, sleep: { _ in })
    }

    /// A controller following a playing fake, as a running layer has it.
    private func running(_ url: URL? = nil) -> PlayerVideoHandoff<FakeVideoPlayback>.Held {
        let playback = FakeVideoPlayback()
        let controller = PlayerVideoController(clock: FakeAudioClock(), songId: "ep1")
        controller.attach(playback)
        return .init(controller: controller, playback: playback, url: url ?? file)
    }

    @Test func aNewLayerTakesOverThePlayerTheOldOneLeft() async {
        let handoff = makeHandoff()
        let old = UUID(), new = UUID()
        let held = running()
        handoff.hold(held, for: key, by: old)

        handoff.letGo(key, by: old, keep: true)
        let taken = handoff.claim(key, by: new)
        await handoff.settle()

        #expect(taken?.controller === held.controller)
        #expect(taken?.playback === held.playback)
        #expect(held.playback.teardowns == 0, "taken over in time: never released")
        #expect(handoff.owns(key, by: new))
    }

    /// The switch to video: nothing is held for the episode yet, so the layer opening its first
    /// file must not read as taken over, or it stops before opening anything and the spinner spins
    /// for ever (seen on the simulator 2026-11-13).
    @Test func aLayerWithNothingHeldYetIsNotTakenOver() {
        let handoff = makeHandoff()
        let layer = UUID()

        #expect(handoff.claim(key, by: layer) == nil)
        #expect(!handoff.isTakenOver(key, from: layer), "the first open goes ahead")

        handoff.hold(running(), for: key, by: layer)
        #expect(!handoff.isTakenOver(key, from: layer))
    }

    @Test func aLayerIsTakenOverOnlyByAnotherLayer() async {
        let handoff = makeHandoff()
        let old = UUID(), new = UUID()
        handoff.hold(running(), for: key, by: old)

        // Let go and waiting: run by no one, so a layer still opening may claim it.
        handoff.letGo(key, by: old, keep: true)
        #expect(!handoff.isTakenOver(key, from: new))

        _ = handoff.claim(key, by: new)
        #expect(handoff.isTakenOver(key, from: old), "the old layer's loop stops on this")
        #expect(!handoff.isTakenOver(key, from: new))
        await handoff.settle()
    }

    @Test func aNewLayerCanTakeOverBeforeTheOldOneLetsGo() async {
        let handoff = makeHandoff()
        let old = UUID(), new = UUID()
        let held = running()
        handoff.hold(held, for: key, by: old)

        // The new page's task can run before the old page's task is torn down.
        let taken = handoff.claim(key, by: new)
        #expect(!handoff.owns(key, by: old), "the old layer's loop stops on this")

        handoff.letGo(key, by: old, keep: true)
        await handoff.settle()

        #expect(taken?.playback === held.playback)
        #expect(held.playback.teardowns == 0)
        #expect(handoff.owns(key, by: new), "the old layer letting go does not touch the new one's player")
    }

    @Test func aNewLayerStartsFromTheHeldPlayerOnItsFirstFrame() {
        let handoff = makeHandoff()
        let held = running()
        handoff.hold(held, for: key, by: UUID())

        #expect(handoff.peek(key)?.controller === held.controller)
        #expect(handoff.peek(key)?.url == file, "a layer that wants another quality can tell")
        #expect(handoff.peek(otherEpisode) == nil, "another episode is a new player")
    }

    @Test func aPlayerNobodyTakesOverIsReleasedWhenTheGraceRunsOut() async {
        let handoff = makeHandoff()
        let old = UUID()
        let held = running()
        handoff.hold(held, for: key, by: old)

        handoff.letGo(key, by: old, keep: true)
        #expect(held.playback.teardowns == 0, "kept for a moment")
        await handoff.settle()

        #expect(held.playback.teardowns == 1)
        #expect(handoff.peek(key) == nil)
        #expect(handoff.claim(key, by: UUID()) == nil)
    }

    @Test func aFailedVideoIsReleasedAtOnceNotKept() {
        let handoff = makeHandoff()
        let old = UUID()
        let held = running()
        handoff.hold(held, for: key, by: old)

        handoff.letGo(key, by: old, keep: false)

        #expect(held.playback.teardowns == 1)
        #expect(handoff.peek(key) == nil)
    }

    @Test func goingOutOfSightReleasesWhateverIsHeld() async {
        let handoff = makeHandoff()
        let old = UUID()
        let held = running()
        handoff.hold(held, for: key, by: old)
        handoff.letGo(key, by: old, keep: true)

        handoff.discard(key)
        await handoff.settle()

        #expect(held.playback.teardowns == 1, "released once, not again when the grace ran out")
        #expect(handoff.peek(key) == nil)
    }

    @Test func aPlayerTakenOverAndLetGoAgainExpiresOnlyOnce() async {
        let handoff = makeHandoff()
        let first = UUID(), second = UUID(), third = UUID()
        let held = running()
        handoff.hold(held, for: key, by: first)

        // Shuffle on, then off again: the player moves page twice.
        handoff.letGo(key, by: first, keep: true)
        _ = handoff.claim(key, by: second)
        handoff.letGo(key, by: second, keep: true)
        _ = handoff.claim(key, by: third)
        await handoff.settle()

        #expect(held.playback.teardowns == 0)
        #expect(handoff.owns(key, by: third))
    }

    @Test func aNewQualityReplacesTheHeldPlayer() {
        let handoff = makeHandoff()
        let owner = UUID()
        let old = running()
        handoff.hold(old, for: key, by: owner)

        // The layer swapped to another file for the same episode.
        let new = running(URL(string: "https://cdn.example/ep1/1080.mp4")!)
        handoff.hold(new, for: key, by: owner)

        #expect(old.playback.teardowns == 1)
        #expect(new.playback.teardowns == 0)
        #expect(handoff.peek(key)?.controller === new.controller, "the next page's layer takes over the new quality")
        #expect(handoff.owns(key, by: owner))
    }

    @Test func eachEpisodeIsHeldOnItsOwn() async {
        let handoff = makeHandoff()
        let a = UUID(), b = UUID()
        let first = running()
        let second = running()
        handoff.hold(first, for: key, by: a)
        handoff.hold(second, for: otherEpisode, by: b)

        handoff.letGo(key, by: a, keep: true)
        await handoff.settle()

        #expect(first.playback.teardowns == 1)
        #expect(second.playback.teardowns == 0)
        #expect(handoff.owns(otherEpisode, by: b))
    }
}
