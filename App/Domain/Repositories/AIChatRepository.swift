import Foundation

/// T58 — the 6 non-streaming AI chat routes. The 7th (SSE send) is
/// deliberately not a protocol method here: `AIChatStreamingClient`
/// (`App/Data/Networking/AIChatStreamingClient.swift`) is a separate,
/// self-contained client on its own `URLSession`, not part of this
/// repository — mirrors `RemoteUserPlaylistRepository`'s own precedent of
/// keeping unrelated-transport concerns (playback, in that codebase's other
/// features) out of a `Repository` protocol entirely.
protocol AIChatRepository: Sendable {
    /// `GET /ai/conversations?cursor=`. `cursor` is `nil` for the first
    /// page. See `AIChatDTOs.swift`'s `AICursorPageDTO.toPaginated(_:)` for
    /// why the returned `Paginated<AIConversation>` can't carry the wire's
    /// own `nextCursor` back out.
    func getConversations(cursor: String?) async throws -> Paginated<AIConversation>

    /// `POST /ai/conversations` — creates and returns a fresh conversation.
    func createConversation() async throws -> AIConversation

    /// `DELETE /ai/conversations/:id`.
    func deleteConversation(id: String) async throws

    /// `GET /ai/conversations/:id/messages?cursor=`. Same cursor/`Paginated<T>`
    /// caveat as `getConversations(cursor:)`.
    func getMessages(conversationID: String, cursor: String?) async throws -> Paginated<AIMessage>

    /// `POST /ai/conversations/:id/messages` — the non-streaming send path
    /// (`AISendPayload.shouldStream == false`, or a streaming caller falling
    /// back after the SSE client fails). Returns both the server's own
    /// persisted echo of the user's message and the assistant's reply.
    func sendMessage(conversationID: String, payload: AISendPayload) async throws -> (userMessage: AIMessage, aiMessage: AIMessage)

    /// `GET /ai/suggestions` — a plain, unpaginated array.
    func getSuggestions() async throws -> [AISuggestion]
}
