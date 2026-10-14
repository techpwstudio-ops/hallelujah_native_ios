import Foundation

enum SongRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
    /// The server's own `message` (Dart toasts `body['message']`).
    case rejected(String)
}

final class RemoteSongRepository: SongRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchSong(id: String) async throws -> Song {
        let response = try await client.send(.songDetail(id: id))
        guard response.statusCode == 200 else {
            throw SongRepositoryError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder().decode(SongDetailResponseDTO.self, from: response.data).data.toDomain()
    }

    func reportSong(id: String, message: String) async throws {
        let body = try JSONEncoder().encode(ReportSongRequestDTO(message: message))
        let response = try await client.send(.reportSong(id: id), body: body)
        guard response.statusCode == 200 else {
            if let serverMessage = try? JSONDecoder().decode(SongMessageResponseDTO.self, from: response.data).message {
                throw SongRepositoryError.rejected(serverMessage)
            }
            throw SongRepositoryError.unexpectedStatus(response.statusCode)
        }
    }
}
