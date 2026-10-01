import Foundation

enum PlaylistRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

final class RemotePlaylistRepository: PlaylistRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchSongs(playlistId: String, owner: PlaylistOwner, page: Int) async throws -> Paginated<Song> {
        let endpoint: Endpoint = switch owner {
        case .company: .companyPlaylistSongs(id: playlistId, page: page)
        case .creator: .playlistSongs(id: playlistId, page: page)
        }
        let response = try await client.send(endpoint)
        guard response.statusCode == 200 else {
            throw PlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(PlaylistSongsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }
}
