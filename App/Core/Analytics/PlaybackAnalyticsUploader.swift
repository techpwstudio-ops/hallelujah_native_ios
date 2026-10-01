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

    func upload(_ events: [QueuedAnalyticsEvent], force: Bool) async -> Bool {
        guard !events.isEmpty else { return true }

        let decoder = JSONDecoder()
        var sessionPayloads: [AnyEncodable] = []
        var trackingEvents: [PlaybackTrackingEvent] = []

        for queued in events {
            switch queued.eventName {
            case "playback_session_start":
                guard let event = try? decoder.decode(PlaybackSessionStartEvent.self, from: queued.payload) else {
                    logger.warning("dropping unreadable playback_session_start event")
                    continue
                }
                sessionPayloads.append(AnyEncodable(event))
            case "playback_session_end":
                guard let event = try? decoder.decode(PlaybackSessionEndEvent.self, from: queued.payload) else {
                    logger.warning("dropping unreadable playback_session_end event")
                    continue
                }
                sessionPayloads.append(AnyEncodable(event))
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

        let user = await currentUserStore.user
        let payload = AnalyticsUploadPayload(
            playbackSessions: sessionPayloads,
            playbackEvents: trackingEvents,
            userDateOfBirth: user?.dateOfBirth,
            userAge: Self.age(fromISODate: user?.dateOfBirth),
            userGender: user?.gender,
            device: await device(),
            force: force
        )

        guard let body = try? JSONEncoder().encode(payload) else {
            logger.warning("failed to encode analytics upload payload")
            return false
        }

        do {
            let response = try await client.send(.sendAnalyticsData, body: body)
            return (200..<300).contains(response.statusCode)
        } catch {
            logger.warning("analytics upload failed: \(error)")
            return false
        }
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
/// "Top-Level Payload" table) — camelCase property names already match its
/// documented keys exactly, so no `CodingKeys` override is needed here
/// (unlike the snake_case per-event/per-device shapes elsewhere in T38).
private struct AnalyticsUploadPayload: Encodable {
    let playbackSessions: [AnyEncodable]
    let playbackEvents: [PlaybackTrackingEvent]
    let userDateOfBirth: String?
    let userAge: Int?
    let userGender: String?
    let device: PlaybackAnalyticsDeviceInfo
    let force: Bool
}

/// Type-erasing wrapper so `PlaybackSessionStartEvent` and
/// `PlaybackSessionEndEvent` — two non-uniform shapes representing the same
/// logical `playbackSessions` row at different phases (see
/// `PlaybackAnalyticsEvents.swift`'s top-level doc comment) — can share one
/// JSON array despite Swift requiring a homogeneous `Encodable` element type.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: some Encodable) {
        encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
