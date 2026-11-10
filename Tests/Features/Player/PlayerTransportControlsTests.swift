import Testing
@testable import Hallelujah

/// Where an episode's back / forward 10 seconds buttons move the playhead.
struct PlayerTransportControlsTests {
    private func target(_ position: Double, _ delta: Double, _ duration: Double?) -> Double {
        PlayerTransportControls.skipTarget(from: position, by: delta, duration: duration)
    }

    @Test func skipIntervalIsTenSeconds() {
        #expect(PlayerTransportControls.skipInterval == 10)
    }

    @Test func forwardMovesTenSecondsAhead() {
        #expect(target(100, 10, 600) == 110)
    }

    @Test func backMovesTenSecondsBack() {
        #expect(target(100, -10, 600) == 90)
    }

    @Test func backNearTheStartStopsAtZero() {
        #expect(target(4, -10, 600) == 0)
        #expect(target(0, -10, 600) == 0)
    }

    @Test func forwardNearTheEndStopsAtTheDuration() {
        #expect(target(595, 10, 600) == 600)
        #expect(target(600, 10, 600) == 600)
    }

    @Test func anUnknownDurationDoesNotLimitForward() {
        #expect(target(100, 10, nil) == 110)
        #expect(target(100, 10, 0) == 110)
        #expect(target(100, 10, -1) == 110)
        #expect(target(100, 10, .infinity) == 110)
    }

    @Test func anUnknownDurationStillStopsBackAtZero() {
        #expect(target(3, -10, nil) == 0)
    }

    @Test func fractionalPositionsKeepTheirFraction() {
        #expect(target(12.5, 10, 600) == 22.5)
        #expect(target(12.5, -10, 600) == 2.5)
    }
}
