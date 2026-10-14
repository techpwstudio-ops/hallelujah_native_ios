import Foundation
import Testing
@testable import GHallelujah

@MainActor
struct AdServeGateTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 5_000)
    }

    private func gate(_ clock: Clock, maxProbeWait: Duration = .seconds(20)) -> AdServeGate {
        AdServeGate(maxProbeWait: maxProbeWait, now: { clock.now })
    }

    @Test func keyIncludesFormatWhenThereIsOne() {
        #expect(AdServeGate.keyFor("p", nil) == "p")
        #expect(AdServeGate.keyFor("p", "audio_ad") == "p:audio_ad")
    }

    @Test func noFillTurnsEveryoneAwayUntilItExpires() async {
        let clock = Clock()
        let gate = gate(clock)
        let turn = await gate.admit("p")
        #expect(turn != nil)
        turn?.noFill()
        #expect(await gate.admit("p") == nil)
        #expect(gate.noFillRemaining("p") == 60)

        clock.now.addTimeInterval(61)
        #expect(gate.noFillRemaining("p") == 0)
        #expect(await gate.admit("p") != nil)
    }

    @Test func noFillHonoursAServerRetryAfter() async {
        let clock = Clock()
        let gate = gate(clock)
        let turn = await gate.admit("p")
        turn?.noFill(retryAfter: 5)
        #expect(gate.noFillRemaining("p") == 5)
    }

    @Test func fillLetsEveryoneStraightThrough() async {
        let clock = Clock()
        let gate = gate(clock)
        let probe = await gate.admit("p")
        probe?.filled()
        #expect(await gate.admit("p") != nil)
        #expect(await gate.admit("p") != nil)
        #expect(gate.noFillRemaining("p") == 0)
    }

    @Test func waitersTakeTheProbesVerdict() async {
        let clock = Clock()
        let gate = gate(clock)
        let probe = await gate.admit("p")
        #expect(probe != nil)

        async let waiterA = gate.admit("p")
        async let waiterB = gate.admit("p")
        // Let both waiters park on the probe before it answers.
        await Task.yield()
        await Task.yield()
        probe?.noFill()

        #expect(await waiterA == nil)
        #expect(await waiterB == nil)
    }

    @Test func waitersAreLetThroughWhenTheProbeFills() async {
        let clock = Clock()
        let gate = gate(clock)
        let probe = await gate.admit("p")

        async let waiter = gate.admit("p")
        await Task.yield()
        await Task.yield()
        probe?.filled()

        #expect(await waiter != nil)
    }

    @Test func failedProbeRemembersNothingButReleasesWaiters() async {
        let clock = Clock()
        let gate = gate(clock)
        let probe = await gate.admit("p")

        async let waiter = gate.admit("p")
        await Task.yield()
        await Task.yield()
        probe?.failed()

        #expect(await waiter == nil)
        // Nothing remembered: the next caller probes afresh.
        #expect(await gate.admit("p") != nil)
    }

    @Test func aWaiterGivesUpOnASlowProbe() async {
        let clock = Clock()
        let gate = gate(clock, maxProbeWait: .milliseconds(30))
        _ = await gate.admit("p")
        #expect(await gate.admit("p") == nil)
    }

    @Test func forceAlwaysAdmitsWithoutOpeningAProbe() async {
        let clock = Clock()
        let gate = gate(clock)
        let first = await gate.admit("p")
        first?.noFill()
        #expect(await gate.admit("p", force: true) != nil)
    }

    @Test func reportingIsIdempotent() async {
        let clock = Clock()
        let gate = gate(clock)
        let turn = await gate.admit("p")
        turn?.filled()
        turn?.noFill()
        turn?.failed()
        #expect(gate.noFillRemaining("p") == 0)
        #expect(await gate.admit("p") != nil)
    }

    @Test func resetForgetsRememberedVerdicts() async {
        let clock = Clock()
        let gate = gate(clock)
        let turn = await gate.admit("p")
        turn?.noFill()
        gate.reset()
        #expect(await gate.admit("p") != nil)
    }
}
