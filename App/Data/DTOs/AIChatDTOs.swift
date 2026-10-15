import Foundation

// MARK: - Message

/// One message row per T58's backend contract's message JSON shape: `id`,
/// `role` (`"user"`/`"assistant"`), `content` (string, may be `null`, may
/// start with the `__TD__` tool-data prefix — see `AIMessage.parseRawContent(raw:)`),
/// `attachments` (`[{key, mimeType}]`), `createdAt`, `language`.
struct AIMessageDTO: Decodable, Sendable {
    let id: String
    let role: AIRole
    let content: String?
    let attachments: [AIAttachmentDTO]?
    let createdAt: String?
    let language: String?
}

extension AIMessageDTO {
    /// Runs raw `content` through `AIMessage.parseRawContent(raw:)` — the
    /// one shared place the `__TD__` tool-data prefix is parsed, so this
    /// decode path and any future live-streaming buffer stay identical.
    func toDomain() -> AIMessage {
        let parsed = AIMessage.parseRawContent(raw: content)
        return AIMessage(
            id: id,
            role: role,
            content: parsed.content,
            toolData: parsed.toolData,
            attachments: (attachments ?? []).map { $0.toDomain() },
            createdAt: Date.parseFlexibleISO8601(createdAt) ?? Date(),
            isStreaming: false,
            isError: false,
            language: language
        )
    }
}

/// A message's `attachments[]` entry — `{key, mimeType}`.
struct AIAttachmentDTO: Decodable, Sendable {
    let key: String
    let mimeType: String?
}

extension AIAttachmentDTO {
    func toDomain() -> AIAttachment {
        AIAttachment(key: key, mimeType: mimeType)
    }
}

// MARK: - Conversation

/// A conversation row per T58's backend contract:
/// `{id, title, lastMessageSnippet, createdAt, updatedAt}`.
struct AIConversationDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let lastMessageSnippet: String?
    let createdAt: String?
    let updatedAt: String?
}

extension AIConversationDTO {
    func toDomain() -> AIConversation {
        AIConversation(
            id: id,
            title: title,
            lastMessageSnippet: lastMessageSnippet,
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt)
        )
    }
}

/// `POST /ai/conversations`'s response — `data: <conversation>`.
struct AIConversationResponseDTO: Decodable, Sendable {
    let data: AIConversationDTO
}

// MARK: - Cursor-paginated list envelope

/// The shared shape of `GET /ai/conversations` and
/// `GET /ai/conversations/:id/messages`'s list envelopes: both wrap
/// `items`/`hasMore`/`nextCursor` together under one `data` object (unlike
/// `UserPlaylistsResponseDTO`, which splits `data` (the array) and `meta`
/// (`page`/`perPage`/`total`/`totalPages`) into separate top-level
/// siblings). Generic over the row DTO, the same way `Paginated<Item>`
/// (`Domain/Entities/Paginated.swift`) is generic over the domain row.
struct AICursorPageDTO<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]?
    let hasMore: Bool?
    let nextCursor: String?
    /// Conversations are page-number paginated in Flutter (`data['page']`).
    let page: Int?

    /// Flutter's `AiService` reads `data['conversations'] ?? data['items']`
    /// for conversations, `data['messages']` for messages and `data['cursor']`
    /// for the next-page token, so every spelling is accepted.
    private enum CodingKeys: String, CodingKey {
        case items, messages, conversations, hasMore, nextCursor, cursor, page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items)
            ?? container.decodeIfPresent([Item].self, forKey: .messages)
            ?? container.decodeIfPresent([Item].self, forKey: .conversations)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? container.decodeIfPresent(String.self, forKey: .cursor)
        page = try? container.decodeIfPresent(Int.self, forKey: .page)
    }
}

extension AICursorPageDTO {
    /// Maps to `Paginated<Domain>`. `nextCursor` rides along on the result for
    /// cursor-paginated messages; `page` is the server's page number for
    /// page-paginated conversations (1 when absent).
    func toPaginated<Domain>(_ transform: (Item) -> Domain) -> Paginated<Domain> {
        let hasMore = hasMore ?? false
        let currentPage = page ?? 1
        return Paginated(
            items: (items ?? []).map(transform),
            page: currentPage,
            perPage: nil,
            total: nil,
            totalPages: hasMore ? currentPage + 1 : currentPage,
            hasMore: hasMore,
            nextCursor: nextCursor
        )
    }
}

/// `GET /ai/conversations`'s response.
struct AIConversationsResponseDTO: Decodable, Sendable {
    let data: AICursorPageDTO<AIConversationDTO>?
}

extension AIConversationsResponseDTO {
    func toDomain() -> Paginated<AIConversation> {
        data?.toPaginated { $0.toDomain() } ?? .empty
    }
}

/// `GET /ai/conversations/:id/messages`'s response.
struct AIMessagesResponseDTO: Decodable, Sendable {
    let data: AICursorPageDTO<AIMessageDTO>?
}

extension AIMessagesResponseDTO {
    func toDomain() -> Paginated<AIMessage> {
        data?.toPaginated { $0.toDomain() } ?? .empty
    }
}

// MARK: - Send message

/// `POST /ai/conversations/:id/messages`'s request body — `{message: String}`
/// only, per the task's backend contract ("non-streaming, JSON body
/// `{ message: string }`").
struct AISendMessageRequestDTO: Encodable, Sendable {
    let message: String?
    let audioKey: String?
    let audioMimeType: String?
    let provider: String?
    let attachments: [AIAttachmentPayloadDTO]?
    let tts: Bool?

    /// `AiSendPayload.toJson`: only populated keys are sent; `attachments`
    /// only when non-empty; `tts` only when true.
    init(payload: AISendPayload) {
        message = payload.message
        audioKey = payload.audioKey
        audioMimeType = payload.audioMimeType
        provider = payload.provider
        attachments = payload.attachments.isEmpty
            ? nil
            : payload.attachments.map { AIAttachmentPayloadDTO(key: $0.key, type: $0.type, mimeType: $0.mimeType) }
        tts = payload.tts ? true : nil
    }
}

/// `AiAttachmentPayload.toJson` — `{key, type, mimeType}`.
struct AIAttachmentPayloadDTO: Encodable, Sendable {
    let key: String
    let type: String
    let mimeType: String
}

/// `POST /ai/conversations/:id/messages`'s response — `data.userMessage`/
/// `data.aiMessage`, both full message objects.
struct AISendMessageDataDTO: Decodable, Sendable {
    let userMessage: AIMessageDTO
    let aiMessage: AIMessageDTO
}

struct AISendMessageResponseDTO: Decodable, Sendable {
    let data: AISendMessageDataDTO
}

// MARK: - Suggestions

/// A suggestion row — `{id, text, category}`.
struct AISuggestionDTO: Decodable, Sendable {
    let id: String
    let text: String
    let category: String?
}

extension AISuggestionDTO {
    func toDomain() -> AISuggestion {
        AISuggestion(id: id, text: text, category: category)
    }
}

/// `GET /ai/suggestions`'s response — `data` is a plain, unpaginated array,
/// not the `items`/`hasMore`/`nextCursor` envelope above.
struct AISuggestionsResponseDTO: Decodable, Sendable {
    let data: [AISuggestionDTO]?
}
