import Foundation
import Observation

/// The player's sleep timer — ports `SetSleepTimerEvent`/`CancelSleepTimerEvent`/
/// `TriggerSleepEvent` and `sleepTimeLeft` (`lib/blocs/player/bloc.dart`).
///
/// One shared instance (registered in `AppComposition`): the timer must keep
/// running while the player screen is closed, and the sheet, the badge and the
/// engine must all see the same deadline. Premium-gated at the call site via
/// `PremiumGate` (`PremiumFeature.sleepTimer`), as `song_menu_sheet.dart` does.
///
/// When the deadline passes the timer stops playback entirely and bumps `firedCount`;
/// the player screen observes that to leave itself (Dart's `popPlayerScreens`),
/// which keeps this type free of any navigation dependency. Playback is stopped
/// here, not in the view, because the timer nearly always fires with the phone
/// locked — no view is alive to do it (the same reason Dart stops from the
/// event handler rather than a post-frame callback).
@MainActor
@Observable
final class SleepTimerController {
    /// `_kOptions` in `sleep_timer_sheet.dart`, in minutes.
    static let options = [5, 10, 15, 30, 45, 60]

    private(set) var selectedMinutes: Int?
    private(set) var endDate: Date?
    private(set) var firedCount = 0

    private let engine: AudioEngine
    private let clock: any ClockProviding
    private var timerTask: Task<Void, Never>?

    init(engine: AudioEngine, clock: any ClockProviding = SystemClock()) {
        self.engine = engine
        self.clock = clock
    }

    var isActive: Bool { endDate != nil }

    /// Seconds until the timer fires; `nil` when none is running. Never negative.
    func remaining() -> TimeInterval? {
        endDate.map { max($0.timeIntervalSince(clock.now()), 0) }
    }

    func start(minutes: Int) {
        start(minutes: minutes, after: .seconds(minutes * 60))
    }

    /// Split from `start(minutes:)` so tests can use a short real delay while
    /// still exercising the same bookkeeping.
    func start(minutes: Int, after delay: Duration) {
        cancel()
        selectedMinutes = minutes
        endDate = clock.now().addingTimeInterval(TimeInterval(minutes * 60))
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    func cancel() {
        timerTask?.cancel()
        timerTask = nil
        selectedMinutes = nil
        endDate = nil
    }

    /// `_onSleepTriggered` -> `StopPlayerEvent`: the timer doesn't just pause,
    /// it ends the session (queue cleared, mini player gone), so the listener
    /// who fell asleep wakes to a quiet, idle app. Position is persisted
    /// first so the song can still be found again.
    private func fire() {
        engine.persistPlaybackPosition()
        if let queueController = DependencyContainer.current.resolveIfRegistered(QueueController.self) {
            queueController.clear()
        } else {
            engine.stop()
        }
        cancel()
        firedCount += 1
    }

    // MARK: - Presentation helpers (pure)

    /// `_SleepBadgePill`'s ring: 0 at the start, 1 at the deadline.
    nonisolated static func progress(remaining: TimeInterval, totalMinutes: Int) -> Double {
        guard totalMinutes > 0 else { return 0 }
        return 1 - min(max(remaining / TimeInterval(totalMinutes * 60), 0), 1)
    }

    /// `_formatTime` in `sleep_timer_badge.dart`: "1h 5m" / "2h" / "12m", with
    /// a started minute counted as a whole one.
    nonisolated static func label(forRemaining remaining: TimeInterval) -> String {
        let seconds = Int(max(remaining, 0))
        let hours = seconds / 3600
        if hours >= 1 {
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        let minutes = seconds / 60 + (seconds % 60 > 0 ? 1 : 0)
        return "\(minutes)m"
    }
}
