import Foundation

enum VerseOfDayRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
    case invalidShareURL
}

/// T56 — `verseOfDay.controller.js` (`/book/verse-of-day/...`). See
/// `VerseOfDayRepository`'s doc comments for the per-method contract this
/// mirrors.
final class RemoteVerseOfDayRepository: VerseOfDayRepository {
    private let client: HTTPClient
    private let cache: VerseOfDayCaching

    init(client: HTTPClient, database: Database) {
        self.client = client
        cache = VerseOfDayCache(database: database)
    }

    func fetchHistory(page: Int) async throws -> Paginated<VerseOfDay> {
        let response = try await client.send(.verseOfDayHistory(page: page))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayHistoryResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    @discardableResult
    func markDelivered(id: String) async throws -> VerseOfDay {
        let response = try await client.send(.markVerseOfDayDelivered(id: id))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayResponseDTO.self, from: response.data)
        let verse = decoded.data.toDomain()
        await cache.store(verse)
        return verse
    }

    @discardableResult
    func markClicked(id: String) async throws -> VerseOfDay? {
        let response = try await client.send(.markVerseOfDayClicked(id: id))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayNullableResponseDTO.self, from: response.data)
        guard let verse = decoded.data?.toDomain() else { return nil }
        await cache.store(verse)
        return verse
    }

    @discardableResult
    func toggleLike(id: String) async throws -> VerseOfDay {
        let response = try await client.send(.toggleVerseOfDayLike(id: id))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayResponseDTO.self, from: response.data)
        let verse = decoded.data.toDomain()
        await cache.store(verse)
        return verse
    }

    func addComment(verseOfDayId: String, content: String) async throws -> VerseOfDayComment {
        let body = try JSONEncoder().encode(AddVerseOfDayCommentRequest(verseOfDayId: verseOfDayId, content: content))
        let response = try await client.send(.addVerseOfDayComment, body: body)
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayCommentResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func fetchComments(verseOfDayId: String, page: Int) async throws -> Paginated<VerseOfDayComment> {
        let response = try await client.send(.verseOfDayComments(verseOfDayId: verseOfDayId, page: page))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayCommentsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    @discardableResult
    func toggleCommentLike(commentId: String) async throws -> VerseOfDayComment {
        let response = try await client.send(.toggleVerseOfDayCommentLike(commentId: commentId))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(VerseOfDayCommentResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func shareURL(id: String) async throws -> URL {
        let response = try await client.send(.verseOfDayShare(id: id))
        guard response.statusCode == 200 else {
            throw VerseOfDayRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(ShareVerseResponseDTO.self, from: response.data)
        guard let url = URL(string: decoded.data.link) else {
            throw VerseOfDayRepositoryError.invalidShareURL
        }
        return url
    }

    func cachedVerse(id: String) async -> VerseOfDay? {
        await cache.verse(id: id)
    }

    func store(_ verse: VerseOfDay) async {
        await cache.store(verse)
    }
}
