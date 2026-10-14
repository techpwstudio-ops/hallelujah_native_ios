import Testing
@testable import GHallelujah

/// The controller's presentation maths is pure and `nonisolated`, so it is
/// tested without an `AudioEngine`; the start/fire path needs a live engine
/// and is covered by the UI/manual pass in `Docs/QA.md`.
struct SleepTimerControllerTests {
    @Test func offeredDurationsMatchTheFlutterSheet() {
        #expect(SleepTimerController.options == [5, 10, 15, 30, 45, 60])
    }

    @Test(arguments: [
        (0.0, "0m"), (1.0, "1m"), (59.0, "1m"), (60.0, "1m"), (61.0, "2m"),
        (600.0, "10m"), (3_599.0, "60m"), (3_600.0, "1h"), (3_660.0, "1h 1m"), (7_200.0, "2h"),
        (-5.0, "0m")
    ])
    func labelFormatsRemainingTime(remaining: Double, expected: String) {
        #expect(SleepTimerController.label(forRemaining: remaining) == expected)
    }

    @Test func progressRunsFromZeroToOne() {
        #expect(SleepTimerController.progress(remaining: 600, totalMinutes: 10) == 0)
        #expect(SleepTimerController.progress(remaining: 300, totalMinutes: 10) == 0.5)
        #expect(SleepTimerController.progress(remaining: 0, totalMinutes: 10) == 1)
    }

    @Test func progressIsClampedAndSafeWithoutATimer() {
        #expect(SleepTimerController.progress(remaining: 9_999, totalMinutes: 10) == 0)
        #expect(SleepTimerController.progress(remaining: -5, totalMinutes: 10) == 1)
        #expect(SleepTimerController.progress(remaining: 100, totalMinutes: 0) == 0)
    }
}
