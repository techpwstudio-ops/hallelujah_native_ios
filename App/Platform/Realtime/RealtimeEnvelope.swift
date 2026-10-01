import Foundation

/// The `{event, data, message, ...}` shape every socket event arrives in —
/// confirmed directly against the backend (`src/socket.io/app.js`'s Redis
/// subscriber: `io.to(room).emit(payload.event, payload)`, so the single
/// emitted argument IS this whole object, not just its `data` field).
/// Mirrors what Dart's handlers read as `event['data']`/`event['message']`/
/// `event['showNotification']` (`lib/services/realtime_event_handler.dart`).
///
/// `data` is `JSONValue` (`Core/Networking/Models/JSONValue.swift`), not a
/// fixed type, because its shape is a different DTO per event name — exactly
/// why that type exists (see its own doc comment).
struct RealtimeEnvelope: Decodable, Sendable {
    let event: String?
    let data: JSONValue?
    let message: String?
    /// `songs.public`'s user-facing foreground-notification fields
    /// (`song.scheduling.js`'s `user` payload branch). Absent on every other
    /// event.
    let showNotification: Bool?
    let title: String?
}

enum RealtimeEnvelopeDecoding {
    /// `SocketAnyEvent.items` (`socket.io-client-swift`) is `[Any]?` — each
    /// element is whatever `JSONSerialization` produced from the wire frame
    /// (`NSDictionary`/`NSArray`/`NSString`/`NSNumber`/`NSNull`). Round-tripping
    /// the first item back through `JSONSerialization` + `JSONDecoder` is the
    /// same bridge `AIStreamEnvelopeDTO`'s `decodedMessage(from:)`
    /// (`AIChatStreamingClient.swift`) uses to get from loosely-typed JSON
    /// onto this app's normal `Decodable` DTOs, reused here rather than
    /// hand-rolling a second `Any`-walking decoder.
    static func envelope(from items: [Any]?) -> RealtimeEnvelope? {
        guard let first = items?.first,
              JSONSerialization.isValidJSONObject(first),
              let data = try? JSONSerialization.data(withJSONObject: first) else {
            return nil
        }
        return try? JSONDecoder().decode(RealtimeEnvelope.self, from: data)
    }
}
