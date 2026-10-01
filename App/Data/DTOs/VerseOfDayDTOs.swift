import Foundation

// MARK: - Verse of day row

/// `verseOfDay.controller.js`'s row shape, confirmed directly against every
/// endpoint that embeds one (`markDelivered`/`markClicked`/`toggleLike`/
/// `getVerseHistory`) — all four send the same flat object.
struct VerseOfDayDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let deliveryStatus: String?
    let image: String?
    let backgroundImage: String?
    let verseId: String?
    let languageName: String?
    let verseText: String?
    let bookName: String?
    let bookNumber: Int?
    let chapterNumber: Int?
    let verseNumber: Int?
    let likes: Int?
    let shares: Int?
    let comments: Int?
    let isLinked: Bool?
    let scheduledAt: String?
    let sentAt: String?
    let createdAt: String?
    let updatedAt: String?
}

extension VerseOfDayDTO {
    func toDomain() -> VerseOfDay {
        VerseOfDay(
            id: id,
            title: verseOfDaySanitized(title),
            deliveryStatus: verseOfDaySanitized(deliveryStatus),
            image: verseOfDaySanitized(image),
            backgroundImage: verseOfDaySanitized(backgroundImage),
            verseId: verseOfDaySanitized(verseId),
            languageName: verseOfDaySanitized(languageName),
            verseText: verseOfDaySanitized(verseText),
            bookName: verseOfDaySanitized(bookName),
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            verseNumber: verseNumber,
            likes: likes ?? 0,
            shares: shares ?? 0,
            comments: comments ?? 0,
            isLiked: isLinked ?? false,
            scheduledAt: Date.parseFlexibleISO8601(scheduledAt),
            sentAt: Date.parseFlexibleISO8601(sentAt),
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt)
        )
    }
}

// MARK: - Single-row envelopes

/// `markDelivered`/`toggleLike`'s shared `{data: <verseOfDay>}` shape —
/// `data` always present on a 200.
struct VerseOfDayResponseDTO: Decodable, Sendable {
    let data: VerseOfDayDTO
}

/// `markClicked`'s `{data: <verseOfDay>|null}` shape — `data` can be `null`
/// on an already-clicked race, confirmed against the controller.
struct VerseOfDayNullableResponseDTO: Decodable, Sendable {
    let data: VerseOfDayDTO?
}

// MARK: - History list envelope

/// `getVerseHistory`'s meta shape (`verseOfDay.controller.js`) — confirmed
/// directly, distinct field order from `UserPlaylistsPaginationMetaDTO` but
/// the same field set (`total`/`totalPages`/`perPage`/`page`). Kept as its
/// own type rather than shared across features, matching this codebase's
/// existing per-feature meta DTO precedent (`UserPlaylistDTOs.swift`).
struct VerseOfDayPaginationMetaDTO: Decodable, Sendable {
    let total: Int?
    let totalPages: Int?
    let perPage: Int?
    let page: Int?
}

struct VerseOfDayHistoryResponseDTO: Decodable, Sendable {
    let data: [VerseOfDayDTO]?
    let meta: VerseOfDayPaginationMetaDTO?
}

extension VerseOfDayHistoryResponseDTO {
    func toDomain() -> Paginated<VerseOfDay> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: (data ?? []).map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.total,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

// MARK: - Comments

/// `commentToVerseOfDay`/`getVerseOfDayComments`/`toggleVerseOfDayCommentLike`
/// (`verseOfDay.controller.js`) — the wire nests `user.{name,image,
/// imageVariants}`; this DTO flattens it at decode time via a custom
/// `init(from:)`, same shape `VerseOfDayComment` itself keeps flat.
struct VerseOfDayCommentDTO: Decodable, Sendable {
    let id: String
    let verseOfDayId: String
    let content: String
    let likes: Int?
    let isLinked: Bool?
    let createdAt: String?
    let updatedAt: String?
    let userId: String?
    let userName: String?
    let userImage: String?
    let userImageVariants: String?

    private enum CodingKeys: String, CodingKey {
        case id, verseOfDayId, content, likes, isLinked, createdAt, updatedAt, user
    }

    /// The wire's nested `user` object — decoded into this small private
    /// shape, then flattened onto the four `user*` fields above.
    private struct UserDTO: Decodable {
        let id: String?
        let name: String?
        let image: String?
        let imageVariants: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        verseOfDayId = try container.decode(String.self, forKey: .verseOfDayId)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        likes = try container.decodeIfPresent(Int.self, forKey: .likes)
        isLinked = try container.decodeIfPresent(Bool.self, forKey: .isLinked)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        let user = try container.decodeIfPresent(UserDTO.self, forKey: .user)
        userId = user?.id
        userName = user?.name
        userImage = user?.image
        userImageVariants = user?.imageVariants
    }
}

extension VerseOfDayCommentDTO {
    func toDomain() -> VerseOfDayComment {
        VerseOfDayComment(
            id: id,
            verseOfDayId: verseOfDayId,
            content: content,
            userId: verseOfDaySanitized(userId),
            userName: verseOfDaySanitized(userName),
            userImage: verseOfDaySanitized(userImage),
            userImageVariants: verseOfDaySanitized(userImageVariants),
            likes: likes ?? 0,
            isLiked: isLinked ?? false,
            createdAt: Date.parseFlexibleISO8601(createdAt),
            updatedAt: Date.parseFlexibleISO8601(updatedAt)
        )
    }
}

struct VerseOfDayCommentResponseDTO: Decodable, Sendable {
    let data: VerseOfDayCommentDTO
}

struct VerseOfDayCommentsResponseDTO: Decodable, Sendable {
    let data: [VerseOfDayCommentDTO]?
    let meta: VerseOfDayPaginationMetaDTO?
}

extension VerseOfDayCommentsResponseDTO {
    func toDomain() -> Paginated<VerseOfDayComment> {
        let page = meta?.page ?? 1
        let totalPages = meta?.totalPages ?? 1
        return Paginated(
            items: (data ?? []).map { $0.toDomain() },
            page: page,
            perPage: meta?.perPage,
            total: meta?.total,
            totalPages: totalPages,
            hasMore: page < totalPages
        )
    }
}

// MARK: - Requests

/// `commentToVerseOfDay`'s body — `{verseOfDayId, content}`.
struct AddVerseOfDayCommentRequest: Encodable, Sendable {
    let verseOfDayId: String
    let content: String
}

// MARK: - Shared helper

private func verseOfDaySanitized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    let lower = trimmed.lowercased()
    if lower == "null" || lower == "undefined" { return nil }
    return trimmed
}
