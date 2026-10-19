import Foundation
import Testing
@testable import Hallelujah

/// A scripted `PlayerAdSource`: hands out the queued ads, counts the asks.
@MainActor
private final class FakePlayerAdSource: PlayerAdSource {
    var timelineValue = AdTimeline(introSeconds: 3, displaySeconds: 5, gapSeconds: 2)
    var everyNValue = 1
    var backoff: TimeInterval = 0
    var queue: [AdCreative?] = []
    var prepareResult = true
    private(set) var serveCount = 0

    func canServe() async -> Bool { true }
    func timeline(_ surface: PlayerAdSurface) -> AdTimeline { timelineValue }
    func everyN(_ surface: PlayerAdSurface) -> Int { everyNValue }
    func backoffRemaining(_ surface: PlayerAdSurface) -> TimeInterval { backoff }

    func serve(_ surface: PlayerAdSurface) async -> AdCreative? {
        serveCount += 1
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    func prepare(_ ad: AdCreative) async -> Bool { prepareResult }
}

/// `PlayerAdController`: the cycle walked a second at a time, no timer, no server.
@MainActor
struct PlayerAdControllerTests {
    private let surface = UUID()

    private func makeController(
        _ source: FakePlayerAdSource,
        now: @escaping () -> Date = { Date() }
    ) -> PlayerAdController {
        let controller = PlayerAdController(source: source, pacing: PlayerAdPacing(), now: now, selfTicking: false)
        controller.surfaceShown(surface)
        controller.setPlaying(true)
        controller.onSong("song-1", isEpisode: false)
        return controller
    }

    /// Ticks once and lets any fetch that tick started finish.
    private func tick(_ controller: PlayerAdController, _ times: Int = 1) async {
        for _ in 0..<times {
            controller.tick()
            await controller.settle()
        }
    }

    @Test func coverStandsAloneThenAdThenCoverAgain() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative(token: "one"), makePlayerAdCreative(token: "two")]
        let controller = makeController(source)

        // Intro 3 s: the ad is asked for 2 s before its turn.
        await tick(controller)
        #expect(controller.ad == nil)
        #expect(source.serveCount == 1)
        await tick(controller)
        #expect(controller.ad == nil)
        // Its turn.
        await tick(controller)
        #expect(controller.ad?.impressionToken == "one")
        #expect(controller.phase == .showing)

        // Shown for 5 s, then the cover comes back for the 2 s gap.
        await tick(controller, 4)
        #expect(controller.ad != nil)
        await tick(controller)
        #expect(controller.ad == nil)
        #expect(controller.phase == .organic)

        // Gap: asked again, a fresh ad each showing.
        await tick(controller, 2)
        #expect(controller.ad?.impressionToken == "two")
    }

    @Test func clockWaitsWhilePausedOrWithNoSurface() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative()]
        let controller = makeController(source)

        controller.setPlaying(false)
        await tick(controller, 10)
        #expect(source.serveCount == 0)

        controller.setPlaying(true)
        controller.surfaceHidden(surface)
        await tick(controller, 10)
        #expect(source.serveCount == 0)

        controller.surfaceShown(surface)
        await tick(controller)
        #expect(source.serveCount == 1)
    }

    @Test func heldOffDropsTheAdAndWaitsForTheCompanionToLeave() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative(token: "one"), makePlayerAdCreative(token: "two")]
        let controller = makeController(source)
        await tick(controller, 3)
        #expect(controller.ad != nil)

        controller.setHeldOff(true)
        #expect(controller.ad == nil)
        let asked = source.serveCount
        await tick(controller, 20)
        #expect(source.serveCount == asked)
        #expect(controller.ad == nil)

        controller.setHeldOff(false)
        await tick(controller, 3)
        #expect(controller.ad?.impressionToken == "two")
    }

    @Test func dismissSendsTheAdAwayForTheGap() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative(token: "one"), makePlayerAdCreative(token: "two")]
        let controller = makeController(source)
        await tick(controller, 3)
        #expect(controller.ad != nil)

        controller.dismiss()
        #expect(controller.ad == nil)
        // Dismissing with no ad up is a no-op.
        controller.dismiss()
        await tick(controller, 2)
        #expect(controller.ad?.impressionToken == "two")
    }

    @Test func noFillBacksOffAtLeastFifteenSeconds() async {
        let source = FakePlayerAdSource()
        source.queue = []
        let controller = makeController(source)
        await tick(controller)
        #expect(source.serveCount == 1)

        // The cover simply stays up; nothing is asked again inside the floor.
        await tick(controller, PlayerAdController.minRetrySeconds - 1)
        #expect(source.serveCount == 1)
        await tick(controller)
        #expect(source.serveCount == 2)
        #expect(controller.ad == nil)
    }

    @Test func serverBackoffLongerThanTheFloorWins() async {
        let source = FakePlayerAdSource()
        source.backoff = 40
        let controller = makeController(source)
        await tick(controller)
        await tick(controller, 39)
        #expect(source.serveCount == 1)
        await tick(controller)
        #expect(source.serveCount == 2)
    }

    @Test func anAdOfTheWrongShapeIsNoAd() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative(assetType: "image_wide_16_9")]
        let controller = makeController(source)
        await tick(controller, 5)
        #expect(controller.ad == nil)
    }

    @Test func anAdWhosePictureWontLoadIsNoAd() async {
        let source = FakePlayerAdSource()
        source.prepareResult = false
        source.queue = [makePlayerAdCreative()]
        let controller = makeController(source)
        await tick(controller, 5)
        #expect(controller.ad == nil)
    }

    @Test func aStaleAdIsDroppedRatherThanShown() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative(token: "old")]
        var clock = Date(timeIntervalSince1970: 1_000)
        let controller = makeController(source, now: { clock })
        await tick(controller, 2)
        clock = clock.addingTimeInterval(PlayerAdController.staleAfter + 1)
        await tick(controller)
        #expect(controller.ad == nil)
    }

    @Test func aNewSongStartsTheCycleOverAndDropsTheAd() async {
        let source = FakePlayerAdSource()
        source.queue = [makePlayerAdCreative(token: "one")]
        let controller = makeController(source)
        await tick(controller, 3)
        #expect(controller.ad != nil)

        controller.onSong("song-2", isEpisode: true)
        #expect(controller.ad == nil)
        #expect(controller.phase == .organic)
        #expect(controller.surface == .episode)

        // Same song reported again: nothing restarts.
        controller.onSong("song-2", isEpisode: true)
        #expect(controller.surface == .episode)
    }

    @Test func noSongStopsEverything() async {
        let source = FakePlayerAdSource()
        let controller = makeController(source)
        controller.onNoSong()
        #expect(!controller.takesOver)
        await tick(controller, 10)
        #expect(source.serveCount == 0)
    }

    @Test func onlyOneSongInNTakesPart() async {
        let source = FakePlayerAdSource()
        source.everyNValue = 2
        let controller = makeController(source)
        #expect(!controller.takesOver)
        controller.onSong("song-2", isEpisode: false)
        #expect(controller.takesOver)
    }
}
