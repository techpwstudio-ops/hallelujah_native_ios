import Foundation

final class AnalyticsService: AnalyticsTracking {
    private let store: AnalyticsEventStore
    private let engine: AnalyticsSyncEngine
    private let logger = AppLogger(category: .analytics)

    init(store: AnalyticsEventStore, engine: AnalyticsSyncEngine) {
        self.store = store
        self.engine = engine
    }

    func track(_ event: any AnalyticsEvent) {
        do {
            try store.enqueue(event)
        } catch {
            logger.warning("failed to enqueue \(event.eventName): \(error)")
            return
        }
        Task { await engine.syncIfNeeded() }
    }

    func flush() async {
        await engine.flush()
    }

    func syncIfNeeded() async {
        await engine.syncIfNeeded()
    }
}
