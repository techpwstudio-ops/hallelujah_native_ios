import Foundation

enum LibraryRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

final class RemoteLibraryRepository: LibraryRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchCounts(songType: HomeContentType) async throws -> LibraryCounts {
        let response = try await client.send(.libraryCount(type: songType))
        guard response.statusCode == 200 else {
            throw LibraryRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(LibraryCountsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func fetchItems(songType: HomeContentType, page: Int) async throws -> Paginated<LibraryEntry> {
        let response = try await client.send(.libraryItems(type: songType, page: page))
        guard response.statusCode == 200 else {
            throw LibraryRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(LibraryItemsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }
}
