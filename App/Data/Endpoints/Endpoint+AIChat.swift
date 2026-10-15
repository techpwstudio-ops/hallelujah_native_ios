import Foundation

/// T58 — AI Assistant chat. Routes per the task's own backend HTTP contract
/// (already grounded before this file was written): `GET/POST
/// /ai/conversations`, `DELETE /ai/conversations/:id`,
/// `GET /ai/conversations/:id/messages`,
/// `POST /ai/conversations/:id/messages`, `GET /ai/suggestions`. A 7th
/// route — the SSE stream, `POST /ai/conversations/:id/messages/stream` — is
/// deliberately absent below: `AIChatStreamingClient`
/// (`App/Data/Networking/AIChatStreamingClient.swift`) builds that request
/// directly against its own `URLSession`, bypassing `Endpoint`/`HTTPClient`
/// entirely, since `HTTPClient` has no streaming support.
extension Endpoint {
    /// `GET /ai/conversations` — `cursor` is left off the query string
    /// entirely on the first page, same optional-query-param convention as
    /// `search(...)`'s `filter`/`userPlaylistId` (`Endpoint.swift`).
    static func aiConversations(cursor: String?, page: Int = 1) -> Endpoint {
        // `AiService.getConversations`: `?page=N&limit=20` (the cursor, when a
        // server sends one, is forwarded too).
        var path = "/ai/conversations?page=\(page)&limit=20"
        if let cursor {
            path += "&cursor=\(aiChatPercentEncoded(cursor))"
        }
        return .get(path)
    }

    /// `POST /ai/conversations` — no body; the server creates a fresh, empty
    /// conversation and returns it as `data`.
    static let createAIConversation = Endpoint.post("/ai/conversations")

    /// `DELETE /ai/conversations/:id`.
    static func deleteAIConversation(id: String) -> Endpoint {
        .delete("/ai/conversations/\(id)")
    }

    /// `GET /ai/conversations/:id/messages` — same `cursor` convention as
    /// `aiConversations(cursor:)` above.
    static func aiMessages(conversationID: String, cursor: String?) -> Endpoint {
        // `AiService.getMessages`: `limit=30` plus the cursor after page one.
        var path = "/ai/conversations/\(conversationID)/messages?limit=30"
        if let cursor {
            path += "&cursor=\(aiChatPercentEncoded(cursor))"
        }
        return .get(path)
    }

    /// `POST /ai/conversations/:id/messages` — the non-streaming send path,
    /// body `{message: String}` (`AISendMessageRequestDTO`).
    static func sendAIMessage(conversationID: String) -> Endpoint {
        .post("/ai/conversations/\(conversationID)/messages")
    }

    /// `GET /ai/suggestions` — `data` is a plain, unpaginated array; no
    /// `cursor`/`page` param at all.
    static let aiSuggestions = Endpoint.get("/ai/suggestions")

    /// Same allowed-character policy as `Endpoint.swift`'s own
    /// `percentEncoded(_:)` — that one is `private` to its own file (Swift's
    /// same-file access rule), so unreachable from here without editing
    /// `Endpoint.swift`, which is out of scope for this task; duplicated
    /// rather than widened. An opaque cursor token can contain `+`/`/`/`=`
    /// (base64url-style encoding), none of which are safe to paste directly
    /// into a query string.
    private static func aiChatPercentEncoded(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}
