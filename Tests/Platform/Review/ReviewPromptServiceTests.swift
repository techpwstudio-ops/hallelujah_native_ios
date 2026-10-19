import Foundation
import Testing
@testable import Hallelujah

@MainActor
struct ReviewPromptServiceTests {
    private final class Box { var requests = 0; var foreground = true; var blocked = false; var date = Date(timeIntervalSince1970: 1_700_000_000) }

    private func make(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        box: Box = Box(),
        policy: ReviewPromptPolicy = ReviewPromptPolicy(minActiveDays: 2, minQualifiedListens: 2)
    ) -> (ReviewPromptService, Box, InMemoryKeyValueStore) {
        let service = ReviewPromptService(
            store: store,
            policy: policy,
            settleDelay: .milliseconds(1),
            now: { box.date },
            isForeground: { box.foreground },
            requestReview: { box.requests += 1 }
        )
        service.isBlocked = { box.blocked }
        return (service, box, store)
    }

    private func openOnTwoDays(_ service: ReviewPromptService, _ box: Box) {
        service.onForeground()
        box.date.addTimeInterval(86_400 * 2)
        service.onForeground()
    }

    @Test func aSecondOpenOnTheSameDayDoesNotCount() {
        let (service, _, _) = make()
        service.onForeground()
        service.onForeground()
        #expect(service.engagement.activeDays == 1)
    }

    @Test func onlyListensOfThirtySecondsQualify() {
        let (service, _, _) = make()
        service.onListenEnded(listenedMs: 29_999, totalDurationMs: 0)
        #expect(service.engagement.qualifiedListens == 0)
        service.onListenEnded(listenedMs: 30_000, totalDurationMs: 0)
        #expect(service.engagement.qualifiedListens == 1)
    }

    @Test func notEligibleUntilBothBarsAreMet() {
        let (service, box, _) = make()
        service.onForeground()
        service.onListenEnded(listenedMs: 60_000, totalDurationMs: 60_000)
        service.onListenEnded(listenedMs: 60_000, totalDurationMs: 60_000)
        service.maybeRequest()
        #expect(box.requests == 0) // only one active day
    }

    @Test func requestsOnceWhenEngagedAndNeverAgain() {
        let (service, box, store) = make()
        openOnTwoDays(service, box)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)
        service.maybeRequest()
        #expect(box.requests == 1)
        #expect(service.requested)
        #expect(store.bool(forKey: ReviewPromptService.requestedKey))
        service.maybeRequest()
        #expect(box.requests == 1)
    }

    @Test func heldBackWhenBackgroundedOrBlockedAndNotSpent() {
        let (service, box, _) = make()
        openOnTwoDays(service, box)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)

        box.foreground = false
        service.maybeRequest()
        box.foreground = true
        box.blocked = true
        service.maybeRequest()
        #expect(box.requests == 0)
        #expect(!service.requested)

        box.blocked = false
        service.maybeRequest()
        #expect(box.requests == 1)
    }

    @Test func spentFlagSurvivesARelaunch() {
        let (service, box, store) = make()
        openOnTwoDays(service, box)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)
        service.maybeRequest()

        let (relaunched, box2, _) = make(store: store)
        #expect(relaunched.requested)
        relaunched.onListenEnded(listenedMs: 40_000, totalDurationMs: 40_000)
        relaunched.maybeRequest()
        #expect(box2.requests == 0)
    }

    @Test func countersPersistAndDamagedStateIsAFreshStart() {
        let store = InMemoryKeyValueStore()
        let (service, _, _) = make(store: store)
        service.onForeground()
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 0)
        let (again, _, _) = make(store: store)
        #expect(again.engagement.activeDays == 1)
        #expect(again.engagement.qualifiedListens == 1)

        store.setData(Data("{".utf8), forKey: ReviewPromptService.engagementKey)
        let (fresh, _, _) = make(store: store)
        #expect(fresh.engagement == ReviewEngagement())
    }

    @Test func finishingASongSchedulesTheRequest() async throws {
        let (service, box, _) = make()
        openOnTwoDays(service, box)
        service.onListenEnded(listenedMs: 40_000, totalDurationMs: 200_000)
        service.onListenEnded(listenedMs: 190_000, totalDurationMs: 200_000) // 95% — finished
        try await Task.sleep(for: .milliseconds(200))
        #expect(box.requests == 1)
    }
}
