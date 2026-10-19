import CoreGraphics
import Testing
@testable import Hallelujah

@MainActor
struct PlayerArtworkPagerTests {
    @Test func pullPastLastPageSkipsNext() {
        #expect(PlayerArtworkPager.edgeAction(translation: -60, index: 4, count: 5) == .next)
    }

    @Test func pullPastFirstPageSkipsPrevious() {
        #expect(PlayerArtworkPager.edgeAction(translation: 60, index: 0, count: 5) == .previous)
    }

    @Test func shortPullOrMiddlePageDoesNothing() {
        #expect(PlayerArtworkPager.edgeAction(translation: -40, index: 4, count: 5) == nil)
        #expect(PlayerArtworkPager.edgeAction(translation: -80, index: 2, count: 5) == nil)
        #expect(PlayerArtworkPager.edgeAction(translation: 80, index: 2, count: 5) == nil)
    }

    @Test func singleSongQueueHonoursBothEdges() {
        #expect(PlayerArtworkPager.edgeAction(translation: -60, index: 0, count: 1) == .next)
        #expect(PlayerArtworkPager.edgeAction(translation: 60, index: 0, count: 1) == .previous)
    }

    @Test func emptyQueueDoesNothing() {
        #expect(PlayerArtworkPager.edgeAction(translation: -60, index: 0, count: 0) == nil)
    }
}
