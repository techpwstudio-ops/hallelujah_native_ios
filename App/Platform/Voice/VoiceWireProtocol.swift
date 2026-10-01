import Foundation

/// T59 — ports `VoiceClientEvents` (`lib/features/voice/net/voice_events.dart`).
/// Confirmed against `src/socket.io/namespaces/voice.namespace.js`'s
/// `socket.on(...)` registrations — every name here is a real, live wire
/// event, none invented.
enum VoiceClientEvent {
    static let hello = "v.hello"
    static let audio = "v.audio"
    static let mark = "v.mark"
    static let barge = "v.barge"
    static let cancel = "v.cancel"
    static let localeSet = "v.locale.set"
    static let sttDevice = "v.stt.device"
    static let bye = "v.bye"
}

/// Ports `VoiceServerEvents` — confirmed against real `session.send(...)` /
/// `turn.orchestrator.js` `session.send(...)` call sites in the backend
/// (`src/services/ai/voice/session.js`, `turn.orchestrator.js`).
enum VoiceServerEventName {
    static let ready = "v.ready"
    static let ack = "v.ack"
    static let speechStart = "v.speech.start"
    static let sttPartial = "v.stt.partial"
    static let sttFinal = "v.stt.final"
    static let replyDelta = "v.reply.delta"
    static let replySentence = "v.reply.sentence"
    static let replyDone = "v.reply.done"
    static let localeChanged = "v.locale.changed"
    static let cancelled = "v.cancelled"
    static let error = "v.error"

    /// Ports `VoiceServerEvents.all` — the subscription list `connect()`
    /// registers a `socket.on(name, ...)` handler for.
    static let all: [String] = [
        ready, ack, speechStart, sttPartial, sttFinal,
        replyDelta, replySentence, replyDone, localeChanged, cancelled, error,
    ]
}

/// Ports `VoiceErrorCodes`.
enum VoiceErrorCode {
    static let netSlow = "net_slow"
    static let netDown = "net_down"
    static let unauthenticated = "unauthenticated"
    static let sttUnavailable = "stt_unavailable"
}

/// Ports `kEngineBackend`/`kEngineDevice`.
enum VoiceEngine: String, Codable, Sendable {
    case backend
    case device
}

// MARK: - Outbound payloads

/// Ports the `v.hello` payload built in `_onConnected()`
/// (`realtime_channel.dart:243`). Optional fields are omitted from the wire
/// message entirely when nil — Dart does this with a collection-if
/// (`if (x != null) 'key': x`); `Encodable`'s default synthesis for
/// `Optional` properties (`encodeIfPresent`) gives the same wire shape for
/// free, so no custom `encode(to:)` is needed.
struct VoiceHelloPayload: Encodable, Sendable {
    var conversationId: String?
    var ttsLocale: String?
    var resumeToken: String?
}

/// Ports the `v.mark` payload (`realtime_channel.dart:353`) — a liveness
/// ping sent on a fixed interval; `tMs` is wall-clock milliseconds at send
/// time, unused by the server beyond logging, but kept for parity.
struct VoiceMarkPayload: Encodable, Sendable {
    var seq: Int
    var tMs: Int
}

/// Ports the `v.barge` payload (`realtime_channel.dart:450`) — sent the
/// instant local VAD fires onset while the assistant is speaking, ahead of
/// the server's own `v.speech.start` by design (see `VoicePhase`'s barge
/// doc comment: "~200ms earlier").
struct VoiceBargePayload: Encodable, Sendable {
    var seq: Int?
}

/// Ports the `v.cancel` payload (`realtime_channel.dart:469`).
struct VoiceCancelPayload: Encodable, Sendable {
    var reason: String
    var seq: Int
}

/// Ports the `v.locale.set` payload (`realtime_channel.dart:480`).
struct VoiceLocaleSetPayload: Encodable, Sendable {
    var ttsLocale: String
    var sttLocale: String?
}

/// Ports the `v.stt.device` payload (`realtime_channel.dart:461`) — a
/// transcript the on-device fallback recognizer produced, shipped up as
/// text on the `engine: "device"` path.
struct VoiceDeviceSttPayload: Encodable, Sendable {
    var text: String
    var language: String?
    var ms: Int
}

// MARK: - Inbound events

/// Ports the `VReady` payload shape from `session.js:288`
/// (`{sessionId, conversationId, resumeToken, engine, sttLocale, ttsLocale}`).
struct VoiceReadyPayload: Decodable, Sendable {
    var sessionId: String?
    var conversationId: String?
    var resumeToken: String?
    var engine: VoiceEngine?
    var sttLocale: String?
    var ttsLocale: String?
}

/// Ports `VAck` (`session.js:498`) — `{seq}`.
struct VoiceAckPayload: Decodable, Sendable {
    var seq: Int
}

/// Ports `VSttPartial` (`session.js:342`) — `{text, stable}`; the server
/// always sends `stable: false` ("the sidecar protocol has no stability
/// signal"), kept here for parity rather than assumed.
struct VoiceSttPartialPayload: Decodable, Sendable {
    var text: String
    var stable: Bool
}

/// Ports `VSttFinal` (`session.js:348,467`) — `{text, language, ms}`.
struct VoiceSttFinalPayload: Decodable, Sendable {
    var text: String
    var language: String?
    var ms: Int?
}

/// Ports `VReplyDelta` (`turn.orchestrator.js:414,454`) — `{text}`.
struct VoiceReplyDeltaPayload: Decodable, Sendable {
    var text: String
}

/// Ports `VReplySentence` (`turn.orchestrator.js:396,430`) —
/// `{seq, text, locale}`.
struct VoiceReplySentencePayload: Decodable, Sendable {
    var seq: Int
    var text: String
    var locale: String?
}

/// Ports `VReplyDone` (`turn.orchestrator.js:300,435,470,545`) —
/// `{messageId, lastSeq}`.
struct VoiceReplyDonePayload: Decodable, Sendable {
    var messageId: String?
    var lastSeq: Int?
}

/// Ports `VLocaleChanged` (`session.js:576,597`) —
/// `{sttLocale, ttsLocale, reason}`.
struct VoiceLocaleChangedPayload: Decodable, Sendable {
    var sttLocale: String?
    var ttsLocale: String?
    var reason: String?
}

/// Ports `VCancelled` (`session.js:551`) — `{fromSeq}`.
struct VoiceCancelledPayload: Decodable, Sendable {
    var fromSeq: Int?
}

/// Ports `VError` (`session.js:177`) — `{code, message, fatal}`.
struct VoiceErrorPayload: Decodable, Sendable {
    var code: String
    var message: String
    var fatal: Bool?
}

/// Ports the `VoiceServerEvent` sealed class
/// (`lib/features/voice/net/voice_events.dart`) as a Swift enum — one case
/// per real server event, each carrying its typed payload.
enum VoiceServerEvent: Sendable {
    case ready(VoiceReadyPayload)
    case ack(VoiceAckPayload)
    case speechStart
    case sttPartial(VoiceSttPartialPayload)
    case sttFinal(VoiceSttFinalPayload)
    case replyDelta(VoiceReplyDeltaPayload)
    case replySentence(VoiceReplySentencePayload)
    case replyDone(VoiceReplyDonePayload)
    case localeChanged(VoiceLocaleChangedPayload)
    case cancelled(VoiceCancelledPayload)
    case error(VoiceErrorPayload)
}

/// Ports `parseVoiceServerEvent(name, payload)` — decodes a socket.io
/// `(name, [Any]?)` pair into a typed `VoiceServerEvent`, returning `nil`
/// for an unrecognized name so an old client can shrug at a server that
/// grew a new event rather than crash the conversation (matches Dart's own
/// forward-compatibility comment at the call site).
///
/// Reuses the `[Any]?` -> `Decodable` bridging idiom from
/// `RealtimeEnvelopeDecoding` (T67, `RealtimeEnvelope.swift`): round-trip
/// the first array element through `JSONSerialization` into `Data`, then
/// `JSONDecoder`.
enum VoiceServerEventParsing {
    static func parse(name: String, items: [Any]?) -> VoiceServerEvent? {
        let raw = items?.first ?? [:]

        func decode<T: Decodable>(_ type: T.Type) -> T? {
            guard JSONSerialization.isValidJSONObject(raw) else { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }

        switch name {
        case VoiceServerEventName.ready:
            guard let payload = decode(VoiceReadyPayload.self) else { return nil }
            return .ready(payload)
        case VoiceServerEventName.ack:
            guard let payload = decode(VoiceAckPayload.self) else { return nil }
            return .ack(payload)
        case VoiceServerEventName.speechStart:
            return .speechStart
        case VoiceServerEventName.sttPartial:
            guard let payload = decode(VoiceSttPartialPayload.self) else { return nil }
            return .sttPartial(payload)
        case VoiceServerEventName.sttFinal:
            guard let payload = decode(VoiceSttFinalPayload.self) else { return nil }
            return .sttFinal(payload)
        case VoiceServerEventName.replyDelta:
            guard let payload = decode(VoiceReplyDeltaPayload.self) else { return nil }
            return .replyDelta(payload)
        case VoiceServerEventName.replySentence:
            guard let payload = decode(VoiceReplySentencePayload.self) else { return nil }
            return .replySentence(payload)
        case VoiceServerEventName.replyDone:
            guard let payload = decode(VoiceReplyDonePayload.self) else { return nil }
            return .replyDone(payload)
        case VoiceServerEventName.localeChanged:
            guard let payload = decode(VoiceLocaleChangedPayload.self) else { return nil }
            return .localeChanged(payload)
        case VoiceServerEventName.cancelled:
            guard let payload = decode(VoiceCancelledPayload.self) else { return nil }
            return .cancelled(payload)
        case VoiceServerEventName.error:
            guard let payload = decode(VoiceErrorPayload.self) else { return nil }
            return .error(payload)
        default:
            return nil
        }
    }
}
