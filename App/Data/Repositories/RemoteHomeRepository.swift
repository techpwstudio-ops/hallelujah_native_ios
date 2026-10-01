import Foundation

enum HomeRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

final class RemoteHomeRepository: HomeRepository {
    private let client: HTTPClient
    private let cache: HomeFeedCache
    private let logger = AppLogger(category: .content)

    init(client: HTTPClient, cache: HomeFeedCache) {
        self.client = client
        self.cache = cache
    }

    func fetchLayout(type: HomeContentType, withSections: Int) async throws -> HomeLayout {
        let response = try await client.send(.homeLayout(type: type, withSections: withSections))
        guard response.statusCode == 200 else {
            throw HomeRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(HomeLayoutResponseDTO.self, from: response.data)
        let layout = decoded.toDomain()
        if layout.degraded {
            // §3.1: a degraded manifest must not be cached for the session.
            logger.warning("home layout degraded — not caching this response")
        } else {
            await cache.store(rawResponse: response.data, type: type)
        }
        return layout
    }

    func cachedLayout(type: HomeContentType) async -> HomeLayout? {
        await cache.load(type: type)
    }

    func fetchFeedWindow(type: HomeContentType, offset: Int, limit: Int) async throws -> HomeFeedWindow {
        let response = try await client.send(.homeFeed(type: type, offset: offset, limit: limit))
        guard response.statusCode == 200 else {
            throw HomeRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(HomeFeedResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func fetchSection(type: HomeContentType, uiId: String, page: Int) async throws -> HomeSectionOutcome {
        let response = try await client.send(.homeSection(type: type, uiId: uiId, page: page))
        guard response.statusCode == 200 else {
            throw HomeRepositoryError.unexpectedStatus(response.statusCode)
        }
        // Same one-level `{data: {...}}` wrapper as every other endpoint in
        // this app (`CurrentUserResponse`, `AuthOTPVerifyResponse`, …), just
        // wrapping a single `HomeSectionResponseDTO` here instead of a list.
        struct Envelope: Decodable { let data: HomeSectionResponseDTO }
        let decoded = try JSONDecoder().decode(Envelope.self, from: response.data)
        return decoded.data.toOutcome()
    }
}
