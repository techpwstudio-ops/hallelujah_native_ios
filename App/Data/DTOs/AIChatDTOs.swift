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
    /// Decoded so it isn't silently dropped at the wire boundary — but see
    /// `toPaginated(_:)` below, which is as far as it can travel.
    let nextCursor: String?
}

extension AICursorPageDTO {
    /// Maps to `Paginated<Domain>`, the return type `AIChatRepository`'s
    /// protocol requires. **Deviation, flagged in T58's build report:**
    /// `Paginated<Item>` was designed for this app's existing *page-number*
    /// pagination (`page`/`perPage`/`total`/`totalPages`/`hasMore` —
    /// `UserPlaylistsResponseDTO.toDomain()` is the precedent this file was
    /// told to mirror), and has no field for an opaque cursor token. So
    /// `hasMore` comes through faithfully (a real wire `Bool`, copied
    /// directly), but the decoded `nextCursor` above cannot be threaded any
    /// further than this DTO — `RemoteAIChatRepository`'s callers see only
    /// `Paginated<AIConversation>`/`Paginated<AIMessage>` and have no way to
    /// obtain the real cursor for their next call through this return type
    /// as specified. Editing `Paginated.swift` or inventing a second,
    /// ai-chat-only paginated type were both out of scope for this task, so
    /// this is the best-effort mapping: `page`/`totalPages` are placeholders
    /// (not meaningful for cursor pagination), and `hasMore` is the one
    /// field downstream code can actually rely on.
    func toPaginated<Domain>(_ transform: (Item) -> Domain) -> Paginated<Domain> {
        let hasMore = hasMore ?? false
        return Paginated(
            items: (items ?? []).map(transform),
            page: 1,
            perPage: nil,
            total: nil,
            totalPages: hasMore ? 2 : 1,
            hasMore: hasMore
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
