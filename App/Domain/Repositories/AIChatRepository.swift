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
    /// page; the next one comes back as `Paginated.nextCursor`.
    func getConversations(cursor: String?, page: Int) async throws -> Paginated<AIConversation>

    /// `POST /ai/conversations` — creates and returns a fresh conversation.
    /// `createConversation({title})` — Flutter titles a chat with the first 60
    /// characters of its first message; `nil` sends an empty body.
    func createConversation(title: String?) async throws -> AIConversation

    /// `DELETE /ai/conversations/:id`.
    func deleteConversation(id: String) async throws

    /// `GET /ai/conversations/:id/messages?cursor=`. Cursor handling as in
    /// `getConversations(cursor:page:)`.
    func getMessages(conversationID: String, cursor: String?) async throws -> Paginated<AIMessage>

    /// `POST /ai/conversations/:id/messages` — the non-streaming send path
    /// (`AISendPayload.shouldStream == false`, or a streaming caller falling
    /// back after the SSE client fails). Returns both the server's own
    /// persisted echo of the user's message and the assistant's reply.
    func sendMessage(conversationID: String, payload: AISendPayload) async throws -> (userMessage: AIMessage, aiMessage: AIMessage)

    /// `GET /ai/suggestions` — a plain, unpaginated array.
    func getSuggestions() async throws -> [AISuggestion]
}

extension AIChatRepository {
    func getConversations(cursor: String?) async throws -> Paginated<AIConversation> {
        try await getConversations(cursor: cursor, page: 1)
    }

    func createConversation() async throws -> AIConversation {
        try await createConversation(title: nil)
    }
}
