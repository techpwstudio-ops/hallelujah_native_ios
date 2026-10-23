import Foundation

enum FavouriteRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

extension Notification.Name {
    /// A song/episode was liked or unliked (server confirmed).
    static let favouriteSongsDidChange = Notification.Name("Hallelujah.favouriteSongsDidChange")
}

final class RemoteFavouriteRepository: FavouriteRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func toggleSongFavorite(songId: String, isFavorited: Bool) async throws {
        let response = try await client.send(.toggleSongFavorite(songId: songId, isFavorited: isFavorited))
        guard response.statusCode == 200 else {
            throw FavouriteRepositoryError.unexpectedStatus(response.statusCode)
        }
        // `_notifyFavouriteChange` (`favourite/bloc.dart`): every toggle site
        // (player, mini player, song menu, Home grid, CarPlay) goes through
        // here, so Library's liked counts/lists update straight away instead
        // of waiting for a pull-to-refresh or filter change.
        await MainActor.run {
            NotificationCenter.default.post(name: .favouriteSongsDidChange, object: nil)
        }
    }

    func fetchFavouriteSongs(type: HomeContentType, page: Int) async throws -> Paginated<Song> {
        let response = try await client.send(.favoriteSongs(type: type, page: page))
        guard response.statusCode == 200 else {
            throw FavouriteRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(FavoriteSongsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func fetchFavouriteCreators(type: HomeContentType, page: Int) async throws -> Paginated<Creator> {
        let response = try await client.send(.favoriteCreators(type: type, page: page))
        guard response.statusCode == 200 else {
            throw FavouriteRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(FavoriteCreatorsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }
}
