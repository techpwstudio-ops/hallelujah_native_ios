import Foundation

enum GenreRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

final class RemoteGenreRepository: GenreRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchGenres() async throws -> [Genre] {
        let response = try await client.send(.dashboardInit)
        guard response.statusCode == 200 else {
            throw GenreRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(DashboardInitGenresDTO.self, from: response.data)
        return decoded.genres.map { $0.toDomain() }
    }

    func fetchSongs(genreID: String, page: Int) async throws -> Paginated<Song> {
        let response = try await client.send(.genreSongs(id: genreID, page: page))
        guard response.statusCode == 200 else {
            throw GenreRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(GenreSongsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }
}
