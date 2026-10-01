import Foundation

/// Ports the *strategy* of `PlaybackEventSyncService` (`tracking_event_sync_service.dart`):
/// purely event-driven (no background timer), time-batched normal syncs,
/// exponential backoff with jitter on failure, and a chunked force-flush
/// that guarantees delivery attempts on logout regardless of batch state.
///
/// One simplification from the Dart original: Dart batches two separate
/// SQLite tables (`playback_sessions` / `playback_events`) with independent
/// aging, because sessions and events there are conceptually different
/// (a session is open/ended, an event is a point in time). This engine
/// queues one generic `AnalyticsEvent` stream instead, so there's only one
/// "oldest queued item" to age-check — collapsing Dart's `minEventsPerBatch`-
/// gated branch (which chose *which* of the two collections' oldest item to
/// check) into a single time-window check. The observable trigger behavior
/// (sync at `maxEventsPerBatch` instantly, otherwise once the oldest item
/// has waited `normalSyncInterval`) is preserved.
///
/// `minEventsPerBatch` is 10 in the Dart *code* — `_kMaxAttempts`-style,
/// `ANALYTICS_PAYLOAD.md` says 8, which is stale relative to its own
/// implementation (same pattern as the T05/T06 doc/code mismatches).
actor AnalyticsSyncEngine {
    static let minEventsPerBatch = 10
    static let maxEventsPerBatch = 500
    static let normalSyncInterval: TimeInterval = 30 * 60
    static let maxLocalEligibilityCheckInterval: TimeInterval = 5 * 60
    static let backoffBase: TimeInterval = 5 * 60
    static let backoffMax: TimeInterval = 30 * 60
    static let forceFlushChunkPause: Duration = .milliseconds(150)

    private let store: AnalyticsEventStore
    private let clock: any ClockProviding
    /// Returns whether the batch was accepted by the backend. `force`
    /// mirrors `ANALYTICS_PAYLOAD.md`'s top-level `force` flag ("`true` on
    /// logout flush — deletes ALL local data after success") — this client
    /// already deletes a batch's rows on ANY successful upload, forced or
    /// not (see `performSync`/`flushAllChunked` below), so the flag has no
    /// client-side behavioral effect; it's threaded through purely so the
    /// backend gets the same "this batch may re-send already-synced rows"
    /// signal Dart's `force: true` payloads carry.
    private let upload: @Sendable ([QueuedAnalyticsEvent], _ force: Bool) async -> Bool
    private let logger = AppLogger(category: .analytics)

    private var isSyncing = false
    private var consecutiveFailures = 0
    private var lastSyncAttempt: Date?
    private var nextNormalSyncCheckAt: Date?

    init(
        store: AnalyticsEventStore,
        clock: any ClockProviding,
        upload: @escaping @Sendable ([QueuedAnalyticsEvent], _ force: Bool) async -> Bool
    ) {
        self.store = store
        self.clock = clock
        self.upload = upload
    }

    /// Call from event-driven triggers (app foreground, network restored,
    /// song session end, …) — never from a timer.
    func syncIfNeeded() async {
        guard !isSyncing else { return }
        await performSync(force: false)
    }

    func flush() async {
        while isSyncing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await performSync(force: true)
    }

    private func performSync(force: Bool) async {
        if !force {
            if consecutiveFailures > 0, let lastSyncAttempt {
                let backoff = backoffDuration(failures: consecutiveFailures)
                guard clock.now().timeIntervalSince(lastSyncAttempt) >= backoff else { return }
            }
            if let nextNormalSyncCheckAt, clock.now() < nextNormalSyncCheckAt { return }
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            if force {
                try await flushAllChunked()
                return
            }

            let events = try store.oldestBatch(limit: Self.maxEventsPerBatch)
            guard !events.isEmpty else { return }
            guard shouldRunNormalSync(events: events) else {
                scheduleNextNormalSyncCheck(events: events)
                return
            }

            nextNormalSyncCheckAt = nil
            lastSyncAttempt = clock.now()

            guard await upload(events, false) else {
                consecutiveFailures += 1
                return
            }
            consecutiveFailures = 0
            try store.delete(ids: events.compactMap(\.id))
        } catch {
            logger.warning("analytics sync failed: \(error)")
            consecutiveFailures += 1
        }
    }

    private func shouldRunNormalSync(events: [QueuedAnalyticsEvent]) -> Bool {
        if events.count >= Self.maxEventsPerBatch { return true }
        guard let oldest = events.first?.enqueuedAt else { return false }
        return clock.now().timeIntervalSince(oldest) >= Self.normalSyncInterval
    }

    private func scheduleNextNormalSyncCheck(events: [QueuedAnalyticsEvent]) {
        guard let oldest = events.first?.enqueuedAt else { return }
        let dueAt = oldest.addingTimeInterval(Self.normalSyncInterval)
        let localRecheckAt = clock.now().addingTimeInterval(Self.maxLocalEligibilityCheckInterval)
        nextNormalSyncCheckAt = min(dueAt, localRecheckAt)
    }

    /// Sends every queued event in capped chunks; stops (leaving the
    /// remainder queued for the next trigger) on the first failed chunk.
    private func flushAllChunked() async throws {
        while true {
            let events = try store.oldestBatch(limit: Self.maxEventsPerBatch)
            guard !events.isEmpty else { break }

            lastSyncAttempt = clock.now()
            guard await upload(events, true) else {
                consecutiveFailures += 1
                break
            }
            consecutiveFailures = 0
            try store.delete(ids: events.compactMap(\.id))
            try? await Task.sleep(for: Self.forceFlushChunkPause)
        }
    }

    private func backoffDuration(failures: Int) -> TimeInterval {
        let exponent = min(max(failures - 1, 0), 9)
        let exponential = Self.backoffBase * pow(2, Double(exponent))
        let capped = min(exponential, Self.backoffMax)
        let jitter = (Double.random(in: 0...1) * 0.5 - 0.25) * capped
        return max(0, capped + jitter)
    }
}
