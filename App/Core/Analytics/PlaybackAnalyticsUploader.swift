import Foundation

/// T38 — supplies `AnalyticsSyncEngine`'s `upload` closure (the
/// `TODO(T38)` stub in `AppComposition`): decodes each generically-queued
/// `QueuedAnalyticsEvent` back into one of the three concrete
/// `PlaybackAnalyticsEvents.swift` shapes by `eventName`, assembles the
/// `ANALYTICS_PAYLOAD.md` top-level body, and POSTs it.
///
/// An `actor`, not a plain `Sendable` class: `cachedDevice` is mutable
/// state written from `upload(_:force:)`, which `AnalyticsSyncEngine` can
/// call concurrently with itself only in the sense that `Task { }` call
/// sites (`AnalyticsService.track`) aren't serialized by anything upstream —
/// the actor gives that write a lock without a manual one.
actor PlaybackAnalyticsUploader {
    private let client: HTTPClient
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .analytics)

    /// Computed once and reused, matching Dart's own `AnalyticsTrackingDataUtils.init()`
    /// being called exactly once per launch — except that call happens
    /// lazily, on this actor, at the first upload attempt rather than
    /// eagerly at splash/session-start, since `AppComposition.installRuntime()`
    /// is synchronous and `PlaybackAnalyticsDeviceInfo.current()` (an
    /// `NWPathMonitor` probe) is not. The few-second difference between
    /// "captured at launch" and "captured at first analytics upload" is not
    /// observable in the payload itself.
    private var cachedDevice: PlaybackAnalyticsDeviceInfo?

    init(client: HTTPClient, currentUserStore: CurrentUserStore) {
        self.client = client
        self.currentUserStore = currentUserStore
    }

    /// Per-request ceilings — the production backend's limits before the
    /// 2026-10-23 ingest fix (`MAX_SESSIONS`/`MAX_EVENTS`). That server sliced
    /// anything above them and still answered 200, and this client deletes the
    /// whole queued batch on a 200 — so a batch carrying more than 50 session
    /// rows (an offline listener easily builds one: up to 500 queue items per
    /// sync) permanently lost every session past the 50th. Staying under them
    /// is safe against both the old and the new server.
    static let maxSessionRowsPerRequest = 50
    static let maxEventsPerRequest = 500

    func upload(_ events: [QueuedAnalyticsEvent], force: Bool) async -> Bool {
        guard !events.isEmpty else { return true }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var sessionRows: [[String: Any]] = []
        var trackingEvents: [PlaybackTrackingEvent] = []

        func appendRow(_ event: some Encodable) {
            guard let data = try? encoder.encode(event),
                  let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                logger.warning("dropping unencodable playback session row")
                return
            }
            sessionRows.append(row)
        }

        for queued in events {
            switch queued.eventName {
            case "playback_session_start":
                guard let event = try? decoder.decode(PlaybackSessionStartEvent.self, from: queued.payload) else {
                    logger.warning("dropping unreadable playback_session_start event")
                    continue
                }
                appendRow(event)
            case "playback_session_end":
                guard let event = try? decoder.decode(PlaybackSessionEndEvent.self, from: queued.payload) else {
                    logger.warning("dropping unreadable playback_session_end event")
                    continue
                }
                appendRow(event)
            case "playback_event":
                guard let event = try? decoder.decode(PlaybackTrackingEvent.self, from: queued.payload) else {
                    logger.warning("dropping unreadable playback_event event")
                    continue
                }
                trackingEvents.append(event)
            default:
                logger.warning("dropping unknown analytics event name \(queued.eventName)")
            }
        }

        let sessions = Self.mergeSessionRows(sessionRows)
        let user = await currentUserStore.user
        let base = AnalyticsUploadPayload(
            userDateOfBirth: user?.dateOfBirth,
            userAge: Self.age(fromISODate: user?.dateOfBirth),
            userGender: user?.gender,
            device: await device(),
            force: force
        )

        // Several requests if needed; every one must succeed before the caller
        // deletes the batch. A partial failure re-sends the whole batch next
        // time, which the server absorbs (sessions are keyed on session_id,
        // events on event_id).
        let requestCount = max(
            Self.chunkCount(sessions.count, Self.maxSessionRowsPerRequest),
            Self.chunkCount(trackingEvents.count, Self.maxEventsPerRequest),
            1
        )
        for index in 0..<requestCount {
            let sessionSlice = Self.slice(sessions, index: index, size: Self.maxSessionRowsPerRequest)
            let eventSlice = Self.slice(trackingEvents, index: index, size: Self.maxEventsPerRequest)
            guard let body = Self.body(base: base, sessions: sessionSlice, events: eventSlice, encoder: encoder) else {
                logger.warning("failed to encode analytics upload payload")
                return false
            }
            do {
                let response = try await client.send(.sendAnalyticsData, body: body)
                guard (200..<300).contains(response.statusCode) else { return false }
            } catch {
                logger.warning("analytics upload failed: \(error)")
                return false
            }
        }
        return true
    }

    /// One row per `session_id`, later rows filling in fields the earlier
    /// ones lacked (a session's START and END rows usually travel together).
    /// Order of first appearance is kept. Mirrors `mergeSessionRows` in
    /// gs_nh_backend `src/services/analytics/trackIngest.js`.
    static func mergeSessionRows(_ rows: [[String: Any]]) -> [[String: Any]] {
        var order: [String] = []
        var merged: [String: [String: Any]] = [:]
        for row in rows {
            guard let id = row["session_id"] as? String, !id.isEmpty else { continue }
            if merged[id] == nil { order.append(id) }
            var current = merged[id] ?? [:]
            for (key, value) in row where !(value is NSNull) {
                current[key] = value
            }
            merged[id] = current
        }
        return order.compactMap { merged[$0] }
    }

    private static func chunkCount(_ count: Int, _ size: Int) -> Int {
        count == 0 ? 0 : (count + size - 1) / size
    }

    private static func slice<T>(_ items: [T], index: Int, size: Int) -> [T] {
        let start = index * size
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + size, items.count)])
    }

    private static func body(
        base: AnalyticsUploadPayload,
        sessions: [[String: Any]],
        events: [PlaybackTrackingEvent],
        encoder: JSONEncoder
    ) -> Data? {
        guard let baseData = try? encoder.encode(base),
              var object = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any],
              let eventsData = try? encoder.encode(events),
              let eventsArray = try? JSONSerialization.jsonObject(with: eventsData) else { return nil }
        object["playbackSessions"] = sessions
        object["playbackEvents"] = eventsArray
        return try? JSONSerialization.data(withJSONObject: object)
    }

    private func device() async -> PlaybackAnalyticsDeviceInfo {
        if let cachedDevice { return cachedDevice }
        let info = await PlaybackAnalyticsDeviceInfo.current()
        cachedDevice = info
        return info
    }

    /// `getAge` (`tracking_event_sync_service.dart:391-402`): whole years
    /// elapsed since `dateOfBirth`, `nil` for an unparseable or future date.
    /// `Calendar.dateComponents([.year], from:to:)` computes the same
    /// "hasn't had this year's birthday yet -> one less" adjustment Dart's
    /// manual month/day comparison does, just via the standard library
    /// instead of by hand.
    private static func age(fromISODate dateString: String?) -> Int? {
        guard let dateString, let dob = parseDate(dateString) else { return nil }
        let years = Calendar(identifier: .gregorian).dateComponents([.year], from: dob, to: Date()).year
        guard let years, years >= 0 else { return nil }
        return years
    }

    /// `DateTime.tryParse` accepts both a bare date and a full ISO8601
    /// datetime; `userDateOfBirth`'s own doc example (`ANALYTICS_PAYLOAD.md`)
    /// is the bare-date form (`"1995-08-14"`), so that's tried first.
    private static func parseDate(_ string: String) -> Date? {
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .iso8601)
        dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

/// The top-level `/analytics/track` request body (`ANALYTICS_PAYLOAD.md`'s
/// "Top-Level Payload" table), minus `playbackSessions`/`playbackEvents`,
/// which `PlaybackAnalyticsUploader.body` adds per request chunk — the session
/// rows are merged as JSON objects (START + END of one session become one row),
/// which a typed `Encodable` array of two different shapes can't express.
/// camelCase property names already match the documented keys exactly.
private struct AnalyticsUploadPayload: Encodable {
    let userDateOfBirth: String?
    let userAge: Int?
    let userGender: String?
    let device: PlaybackAnalyticsDeviceInfo
    let force: Bool
}
