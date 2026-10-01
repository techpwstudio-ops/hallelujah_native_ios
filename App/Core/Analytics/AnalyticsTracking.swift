protocol AnalyticsTracking: Sendable {
    /// Fire-and-forget — enqueues locally and returns immediately; never
    /// blocks or throws on the caller.
    func track(_ event: any AnalyticsEvent)

    /// Sends every queued event before returning, in capped chunks —
    /// mirrors `force: true` in the Flutter sync service. Called on logout.
    func flush() async

    /// Event-driven sync trigger (T19) — call on network reconnect. Mirrors
    /// `NetworkStatusBloc` calling `PlaybackEventSyncService().syncPendingData()`
    /// on `wasOffline && !nowOffline` (`lib/blocs/network/bloc.dart`). Not
    /// forced: respects `AnalyticsSyncEngine`'s own batching/backoff gates,
    /// same as what `track(_:)` triggers internally.
    func syncIfNeeded() async
}
