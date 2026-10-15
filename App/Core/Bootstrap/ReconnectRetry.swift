import Foundation

/// Port of `ReconnectRetry` (`lib/services/reconnect_retry.dart`): re-runs a
/// failed load until it succeeds — on a backoff schedule while the device
/// looks online, and immediately whenever connectivity comes back.
///
/// Built for loads that matter but ran once (the `/dashboard/init` payload at
/// cold start), where a launch with no signal otherwise left the app on
/// defaults for the whole session. Connectivity is injected so the logic is
/// testable without the platform monitor.
@MainActor
final class ReconnectRetry {
    static let defaultBackoff: [Duration] = [.seconds(5), .seconds(15), .seconds(30), .seconds(60), .seconds(120)]

    /// One try. Returns `true` when it succeeded, which ends the retrying.
    private let attempt: @MainActor () async -> Bool
    private let isOnline: @MainActor () -> Bool
    /// Emits `true` each time the device goes (back) online.
    private let onlineChanges: AsyncStream<Bool>
    /// Waits between timed retries. Once spent, only an online event retries
    /// again — a device that stays online with a failing server is not
    /// hammered.
    private let backoff: [Duration]

    private var listenTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var step = 0
    private var running = false

    init(
        attempt: @escaping @MainActor () async -> Bool,
        onlineChanges: AsyncStream<Bool>,
        isOnline: @escaping @MainActor () -> Bool,
        backoff: [Duration] = ReconnectRetry.defaultBackoff
    ) {
        self.attempt = attempt
        self.onlineChanges = onlineChanges
        self.isOnline = isOnline
        self.backoff = backoff
    }

    /// Whether retrying is armed.
    var isArmed: Bool { listenTask != nil }

    /// Starts (or re-schedules) retrying. Call it after a failed attempt of
    /// your own; calling it again while armed is harmless.
    func arm() {
        if listenTask == nil {
            let changes = onlineChanges
            listenTask = Task { [weak self] in
                for await online in changes {
                    guard let self else { return }
                    if !online { continue }
                    // A fresh connection is a fresh chance: restart the backoff.
                    self.step = 0
                    self.timerTask?.cancel()
                    self.timerTask = nil
                    await self.fire()
                }
            }
        }
        // A retry is already pending or running (`fire` re-arms itself when
        // its attempt fails): leave it be, so arming twice neither moves the
        // timer nor burns a backoff step.
        if running || timerTask != nil { return }
        // Offline, or out of timed retries: wait for the next online event.
        if !isOnline() || step >= backoff.count { return }
        let delay = backoff[step]
        step += 1
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.fire()
        }
    }

    /// Stops retrying and forgets the backoff position.
    func cancel() {
        listenTask?.cancel()
        listenTask = nil
        timerTask?.cancel()
        timerTask = nil
        step = 0
    }

    private func fire() async {
        // Called from the timer task itself, which must not be cancelled
        // (the attempt does network I/O) — only forget it.
        timerTask = nil
        if running || !isOnline() { return }
        running = true
        let succeeded = await attempt()
        running = false
        // `cancel()` during the attempt (logout) leaves nothing armed: stay stopped.
        guard listenTask != nil else { return }
        if succeeded {
            cancel()
        } else {
            arm()
        }
    }
}
