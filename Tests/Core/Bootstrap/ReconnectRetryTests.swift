import Testing
@testable import Hallelujah

@MainActor
private final class Attempts {
    var count = 0
    var results: [Bool]
    init(_ results: [Bool]) { self.results = results }

    func next() -> Bool {
        count += 1
        return results.isEmpty ? true : results.removeFirst()
    }
}

@MainActor
private final class OnlineFlag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@MainActor
struct ReconnectRetryTests {
    @Test func retriesOnTheBackoffUntilItSucceeds() async throws {
        let attempts = Attempts([false, false, true])
        let (stream, _) = AsyncStream<Bool>.makeStream()
        let retry = ReconnectRetry(
            attempt: { attempts.next() },
            onlineChanges: stream,
            isOnline: { true },
            backoff: [.milliseconds(10), .milliseconds(10), .milliseconds(10)]
        )
        retry.arm()
        try await Task.sleep(for: .milliseconds(300))
        #expect(attempts.count == 3)
        #expect(!retry.isArmed) // success ends it
    }

    @Test func staysIdleWhileOfflineThenRetriesWhenConnectivityReturns() async throws {
        let attempts = Attempts([true])
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let online = OnlineFlag(false)
        let retry = ReconnectRetry(
            attempt: { attempts.next() },
            onlineChanges: stream,
            isOnline: { online.value },
            backoff: [.milliseconds(10)]
        )
        retry.arm()
        try await Task.sleep(for: .milliseconds(100))
        #expect(attempts.count == 0) // offline: no timed retry

        online.value = true
        continuation.yield(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(attempts.count == 1)
        #expect(!retry.isArmed)
    }

    @Test func cancelStopsEverything() async throws {
        let attempts = Attempts([false, false, false])
        let (stream, _) = AsyncStream<Bool>.makeStream()
        let retry = ReconnectRetry(
            attempt: { attempts.next() },
            onlineChanges: stream,
            isOnline: { true },
            backoff: [.milliseconds(50)]
        )
        retry.arm()
        retry.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(attempts.count == 0)
        #expect(!retry.isArmed)
    }

    @Test func outOfBackoffStepsWaitsForAnOnlineEvent() async throws {
        let attempts = Attempts([false, false])
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let retry = ReconnectRetry(
            attempt: { attempts.next() },
            onlineChanges: stream,
            isOnline: { true },
            backoff: [.milliseconds(10)]
        )
        retry.arm()
        try await Task.sleep(for: .milliseconds(150))
        #expect(attempts.count == 1) // one timed retry, then nothing

        // A reconnect retries at once (2nd attempt, fails) and restarts the
        // backoff, so one more timed retry follows (3rd, succeeds and stops).
        continuation.yield(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(attempts.count == 3)
        #expect(!retry.isArmed)
        retry.cancel()
    }
}
