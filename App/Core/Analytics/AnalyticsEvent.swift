/// Anything trackable. Concrete event types land with the feature that
/// fires them (e.g. playback session/progress events with T38) — nothing
/// pre-declared here.
protocol AnalyticsEvent: Sendable, Encodable {
    /// The event name as sent to the backend, e.g. "playback_start".
    var eventName: String { get }
}
