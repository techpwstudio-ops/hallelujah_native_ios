import Foundation

/// T59 — ports `ReconnectPolicy` (`lib/features/voice/net/reconnect_policy.dart`)
/// verbatim, including the exact 6-rung schedule and comments explaining why
/// it's a fixed ladder (not computed exponential backoff) and why jitter
/// isn't decoration (a stadium full of phones losing the tower at the same
/// instant must not all retry on the same millisecond and knock the server
/// over together).
///
/// A fixed ladder rather than a computed exponential: the first rung is
/// deliberately tiny (250ms) because most voice-socket drops are a cell/
/// Wi-Fi handover that is already over by the time it's noticed, and a 1s
/// first retry is audible as dead air mid-conversation.
final class VoiceReconnectPolicy: @unchecked Sendable {
    private static let defaultScheduleMs: [Int] = [250, 500, 1000, 2000, 4000, 8000]

    private let scheduleMs: [Int]
    private let jitterFraction: Double
    private var attemptCount = 0
    private let lock = NSLock()

    init(scheduleMs: [Int] = VoiceReconnectPolicy.defaultScheduleMs, jitterFraction: Double = 0.2) {
        self.scheduleMs = scheduleMs
        self.jitterFraction = jitterFraction
    }

    /// How many delays have been handed out since the last `reset()`.
    var attempt: Int {
        lock.lock()
        defer { lock.unlock() }
        return attemptCount
    }

    /// True once the ladder is sitting on its last rung.
    var atCeiling: Bool {
        lock.lock()
        defer { lock.unlock() }
        return attemptCount >= scheduleMs.count
    }

    /// The next wait, with +/- `jitterFraction` applied. Advances the
    /// ladder; once the top rung is reached every further call returns that
    /// rung (re-jittered) — the policy never gives up on its own, because a
    /// voice conversation is ended by the user or by a fatal server error,
    /// not by running out of patience.
    func nextDelay() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        let base = scheduleMs[min(attemptCount, scheduleMs.count - 1)]
        attemptCount += 1

        // (1 - f) .. (1 + f)
        let factor = 1 + (Double.random(in: 0 ... 1) * 2 - 1) * jitterFraction
        let ms = (Double(base) * factor).rounded()
        return .milliseconds(Int(ms))
    }

    /// Call on every successful connect. Forgetting this is the classic bug:
    /// the ladder stays at 8s and a flaky link never recovers quickly again.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        attemptCount = 0
    }
}
