/// T38 — the three `AnalyticsEvent` shapes `PlaybackAnalyticsRecorder`
/// enqueues, matching `ANALYTICS_PAYLOAD.md`'s `playbackSessions`/
/// `playbackEvents` field names/types exactly (backend-contract-critical —
/// these are read directly by the real `/api/sendAnalyticsData` endpoint,
/// not an internal implementation detail free to rename).
///
/// The generic `AnalyticsEventStore`/`QueuedAnalyticsEvent` queue this
/// codebase already has (pre-T38 scaffolding, see `AnalyticsSyncEngine`'s
/// own doc comment) is append-only — it has no row-mutation story, unlike
/// Dart's SQLite `playback_sessions` table, whose `ended_at`/
/// `song_end_duration_ms`/`loop_play_number` columns get UPDATEd after the
/// row is first inserted. Rather than bolt mutation onto the generic queue,
/// a session is split into two independent, immutable events —
/// `PlaybackSessionStartEvent` and `PlaybackSessionEndEvent`, both carrying
/// `sessionID` — and `PlaybackAnalyticsUploader` turns each into its own
/// PARTIAL `playbackSessions` row at send time. This is safe specifically
/// because `ANALYTICS_PAYLOAD.md`'s own backend checklist already documents
/// `session_id` as an upsert key ("duplicate inserts are idempotent... update
/// `ended_at` if a later batch sends the same `session_id`") — sending a
/// start-row now and an end-row in a later sync batch is exactly the
/// two-phase upsert the backend already expects, not a native workaround.
///
/// Timestamps are plain `Int` epoch-milliseconds (`DateTime.now()
/// .millisecondsSinceEpoch`'s exact wire shape), not `Date` — `Date`'s
/// default `Encodable` conformance writes seconds-since-1970 as a `Double`,
/// which would silently mismatch `ANALYTICS_PAYLOAD.md`'s documented
/// integer-milliseconds type; representing the field as the wire type
/// directly avoids relying on every encoder in the store/upload path
/// sharing one non-default `dateEncodingStrategy`.
struct PlaybackSessionStartEvent: AnalyticsEvent, Decodable {
    var eventName: String { "playback_session_start" }

    let sessionID: String
    let songID: String
    let creatorID: String?
    let primaryGenreID: String?
    let type: String?
    let playSource: String?
    let startedAtMS: Int
    let songDurationMS: Int
    let audioQuality: String?
    let planID: String?
    let planName: String?
    let batteryLevel: Int?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case songID = "song_id"
        case creatorID = "creator_id"
        case primaryGenreID = "primary_genre_id"
        case type
        case playSource = "play_source"
        case startedAtMS = "started_at"
        case songDurationMS = "song_duration_ms"
        case audioQuality = "audio_quality"
        case planID = "plan_id"
        case planName = "plan_name"
        case batteryLevel = "battery_level"
    }
}

struct PlaybackSessionEndEvent: AnalyticsEvent, Decodable {
    var eventName: String { "playback_session_end" }

    let sessionID: String
    let endedAtMS: Int
    let songEndDurationMS: Int
    let loopPlayNumber: Int
    let isSuspectedFraud: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case endedAtMS = "ended_at"
        case songEndDurationMS = "song_end_duration_ms"
        case loopPlayNumber = "loop_play_number"
        case isSuspectedFraud = "is_suspected_fraud"
    }
}

/// `event_type` values, `ANALYTICS_PAYLOAD.md`'s own enum table — matches
/// `PlaybackEventType` (`SongAnalyticsManager.dart:20-28`) exactly. `Decodable`
/// (not just `Encodable`) because `PlaybackAnalyticsUploader` decodes
/// `PlaybackTrackingEvent` back out of the generic queue's stored JSON.
enum PlaybackEventKind: String, Sendable, Codable {
    case start, progress, pause, resume
    case seekForward, seekBackward
    case end
}

struct PlaybackTrackingEvent: AnalyticsEvent, Decodable {
    var eventName: String { "playback_event" }

    /// `ANALYTICS_PAYLOAD.md`'s `playbackEvents.id` — "same value as
    /// `event_id`" — the backend contract lists them as two separate JSON
    /// keys despite always being equal, so both are sent rather than
    /// collapsed into one.
    let id: String
    let eventID: String
    let sessionID: String
    let songID: String
    let creatorID: String?
    let type: String?
    let eventType: PlaybackEventKind
    let positionMS: Int
    let appState: String
    let networkState: String
    let audioQuality: String?
    let batteryLevel: Int?
    let outputDeviceName: String?
    let eventTimeMS: Int

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case sessionID = "session_id"
        case songID = "song_id"
        case creatorID = "creator_id"
        case type
        case eventType = "event_type"
        case positionMS = "position_ms"
        case appState = "app_state"
        case networkState = "network_state"
        case audioQuality = "audio_quality"
        case batteryLevel = "battery_level"
        case outputDeviceName = "output_device_name"
        case eventTimeMS = "event_time"
    }
}
