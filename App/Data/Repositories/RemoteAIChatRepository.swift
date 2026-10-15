import Foundation

enum AIChatRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

/// T58 — the 6 non-streaming AI chat routes. `AIChatStreamingClient`
/// (`App/Data/Networking/AIChatStreamingClient.swift`) covers the 7th (SSE
/// send) on its own `URLSession`, entirely outside this repository —
/// mirrors `RemoteUserPlaylistRepository`'s structure (`let client:
/// HTTPClient`, one method per route, decode-then-`toDomain()`).
final class RemoteAIChatRepository: AIChatRepository {
    let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func getConversations(cursor: String?, page: Int) async throws -> Paginated<AIConversation> {
        let response = try await client.send(.aiConversations(cursor: cursor, page: page))
        guard response.statusCode == 200 else {
            throw AIChatRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(AIConversationsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func createConversation(title: String?) async throws -> AIConversation {
        let payload: [String: String] = title.map { ["title": $0] } ?? [:]
        let body = try JSONEncoder().encode(payload)
        let response = try await client.send(.createAIConversation, body: body)
        guard response.statusCode == 200 else {
            throw AIChatRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(AIConversationResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func deleteConversation(id: String) async throws {
        let response = try await client.send(.deleteAIConversation(id: id))
        // "200/204, no meaningful body" — the task's own backend HTTP
        // contract for this route.
        guard response.statusCode == 200 || response.statusCode == 204 else {
            throw AIChatRepositoryError.unexpectedStatus(response.statusCode)
        }
    }

    func getMessages(conversationID: String, cursor: String?) async throws -> Paginated<AIMessage> {
        let response = try await client.send(.aiMessages(conversationID: conversationID, cursor: cursor))
        guard response.statusCode == 200 else {
            throw AIChatRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(AIMessagesResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func sendMessage(conversationID: String, payload: AISendPayload) async throws -> (userMessage: AIMessage, aiMessage: AIMessage) {
        let body = try JSONEncoder().encode(AISendMessageRequestDTO(payload: payload))
        let response = try await client.send(.sendAIMessage(conversationID: conversationID), body: body)
        guard response.statusCode == 200 else {
            throw AIChatRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(AISendMessageResponseDTO.self, from: response.data)
        return (decoded.data.userMessage.toDomain(), decoded.data.aiMessage.toDomain())
    }

    func getSuggestions() async throws -> [AISuggestion] {
        let response = try await client.send(.aiSuggestions)
        guard response.statusCode == 200 else {
            throw AIChatRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(AISuggestionsResponseDTO.self, from: response.data)
        return (decoded.data ?? []).map { $0.toDomain() }
    }
}
