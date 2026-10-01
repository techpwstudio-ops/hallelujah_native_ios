import Foundation

enum SearchRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

final class RemoteSearchRepository: SearchRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func search(
        query: String,
        filter: SearchFilter?,
        musicPage: Int,
        episodePage: Int,
        creatorPage: Int,
        playlistPage: Int,
        userPlaylistId: String?
    ) async throws -> SearchResults {
        let response = try await client.send(.search(
            query: query,
            filter: filter,
            musicPage: musicPage,
            episodePage: episodePage,
            creatorPage: creatorPage,
            playlistPage: playlistPage,
            userPlaylistId: userPlaylistId
        ))
        guard response.statusCode == 200 else {
            throw SearchRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(SearchResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }
}
