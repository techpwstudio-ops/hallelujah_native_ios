import Foundation

/// One event off the SSE stream. `AIMessage.isStreamingPlaceholder`/`.delta`
/// text is what a consuming ViewModel accumulates into the placeholder row
/// while streaming; `.done`/`.cancelled`/`.error` each end the stream.
enum AIStreamEvent: Sendable {
    case delta(String)
    case done(AIMessage)
    case cancelled(AIMessage)
    case error(String)
}

enum AIChatStreamingError: Error, Sendable, Equatable {
    case invalidURL
    case unexpectedStatus(Int)
}

/// T58 — `POST /ai/conversations/:id/messages/stream`, the one AI chat route
/// `AIChatRepository`/`RemoteAIChatRepository` deliberately don't cover.
/// Self-contained on its own `URLSession`: `HTTPClient` (`Core/Networking/
/// Client/HTTPClient.swift`) has no streaming support (it always awaits a
/// single complete `(Data, URLResponse)` via `session.data(for:)`), so this
/// doesn't go through it — but it still replicates `HTTPClient`'s own
/// token-fetch (`AuthTokenProviding.currentAccessToken()`) and
/// `Authorization`/`secure` header construction exactly, rather than
/// inventing a second auth mechanism. Unlike `HTTPClient`, this does not
/// retry on a 401 — the task's own streaming spec only asks to replicate
/// token-fetch/header-building, not `HTTPClient`'s full single-flight
/// refresh-and-replay policy, and a mid-stream reauth-and-restart is a
/// ViewModel-level retry concern, not this client's.
final class AIChatStreamingClient: Sendable {
    private let configuration: AppConfiguration
    private let authProvider: any AuthTokenProviding
    private let session: URLSession
    private let logger = AppLogger(category: .aiChat)

    init(configuration: AppConfiguration, authProvider: any AuthTokenProviding, session: URLSession? = nil) {
        self.configuration = configuration
        self.authProvider = authProvider
        self.session = session ?? URLSession(configuration: .default)
    }

    /// One event stream per call — not reusable across sends. The consumer
    /// (a future ViewModel) iterates this with `for try await event in
    /// stream`.
    func streamMessage(conversationID: String, payload: AISendPayload) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runStream(conversationID: conversationID, payload: payload, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        conversationID: String,
        payload: AISendPayload,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        let request = try await makeRequest(conversationID: conversationID, payload: payload)
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AIChatStreamingError.unexpectedStatus(statusCode)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            var payloadText = String(line.dropFirst("data:".count))
            if payloadText.hasPrefix(" ") {
                payloadText.removeFirst()
            }

            // Fallback terminator — the primary ones are the "done"/
            // "cancelled"/"error" `type`s handled below, per the backend's
            // own documented SSE format.
            if payloadText.isEmpty || payloadText == "[DONE]" {
                return
            }

            guard let eventData = payloadText.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(AIStreamEnvelopeDTO.self, from: eventData) else {
                continue
            }

            switch envelope.type {
            case "delta":
                if let text = envelope.delta ?? envelope.content {
                    continuation.yield(.delta(text))
                }
            case "done":
                if let message = decodedMessage(from: envelope.message) {
                    continuation.yield(.done(message.toDomain()))
                }
                return
            case "cancelled":
                if let message = decodedMessage(from: envelope.message) {
                    continuation.yield(.cancelled(message.toDomain()))
                }
                return
            case "error":
                // `ai_service.dart` throws a fixed message for the server's
                // error event; the server's own text is never shown.
                _ = stringValue(from: envelope.message)
                continuation.yield(.error("Something went wrong, please try again after sometime."))
                return
            case "user_message", "tts_ready":
                continue
            default:
                // Unrecognized type — skip, keep reading.
                continue
            }
        }
    }

    private func makeRequest(conversationID: String, payload: AISendPayload) async throws -> URLRequest {
        let path = "/ai/conversations/\(conversationID)/messages/stream"
        // Same plain string concatenation as `HTTPClient.makeRequest(for:body:)`
        // — a path starting with "/" would otherwise replace `apiBaseURL`'s
        // own "/api" path component via `URL(string:relativeTo:)` instead of
        // appending to it.
        guard let url = URL(string: configuration.apiBaseURL.absoluteString + path) else {
            throw AIChatStreamingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Body carries only `message` — attachments/audioKey are out of
        // scope (no attachment or voice/TTS send path in T58 v1).
        request.httpBody = try JSONEncoder().encode(AIStreamRequestBodyDTO(message: payload.message))

        let token = await authProvider.currentAccessToken() ?? ""
        request.allHTTPHeaderFields = [
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "Authorization": "Bearer \(token)",
            "secure": configuration.apiSecureHeader,
        ]
        return request
    }

    /// `"done"`/`"cancelled"` events embed a `message` object; decoding it
    /// through `AIMessageDTO` (not a bespoke streaming-only shape) is what
    /// puts it on the exact same `AIMessage.parseRawContent(raw:)` path as
    /// every other message decode.
    private func decodedMessage(from value: JSONValue?) -> AIMessageDTO? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(AIMessageDTO.self, from: data)
    }

    /// `"error"` events' `message` field is a plain string, not an object —
    /// the two event types share a JSON key name but not a value type,
    /// which is exactly why `AIStreamEnvelopeDTO.message` below is decoded
    /// as `JSONValue` rather than one fixed Swift type.
    private func stringValue(from value: JSONValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }
}

/// `POST /ai/conversations/:id/messages/stream`'s request body — `{message:
/// String}` only.
private struct AIStreamRequestBodyDTO: Encodable, Sendable {
    let message: String?
}

/// One decoded SSE `data:` payload. `message` is `JSONValue`
/// (`Core/Networking/Models/JSONValue.swift`) rather than a fixed type
/// because its shape depends on `type`: an embedded message object for
/// `"done"`/`"cancelled"`, a plain string for `"error"`.
private struct AIStreamEnvelopeDTO: Decodable, Sendable {
    let type: String
    let delta: String?
    let content: String?
    let message: JSONValue?
}
