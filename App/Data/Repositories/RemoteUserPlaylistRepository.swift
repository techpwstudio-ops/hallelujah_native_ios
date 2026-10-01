import Foundation

enum UserPlaylistRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
    /// `fetchSongs`' 200 response arrived with no `playlist` sibling key —
    /// shouldn't happen (the endpoint 404s first if the playlist itself is
    /// missing), but `UserPlaylistSongsResponseDTO.toDomain()` has no domain
    /// default worth inventing for a missing owner.
    case missingPlaylist
}

final class RemoteUserPlaylistRepository: UserPlaylistRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchPlaylists(page: Int) async throws -> Paginated<UserPlaylist> {
        let response = try await client.send(.userPlaylists(page: page))
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(UserPlaylistsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func fetchPlaylist(id: String) async throws -> UserPlaylist {
        let response = try await client.send(.userPlaylist(id: id))
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(UserPlaylistResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func createPlaylist(title: String, songID: String?) async throws -> UserPlaylist {
        let body = try JSONEncoder().encode(CreateUserPlaylistRequest(title: title, songId: songID))
        let response = try await client.send(.createUserPlaylist, body: body)
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(UserPlaylistResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func renamePlaylist(id: String, title: String) async throws -> UserPlaylist {
        let body = try JSONEncoder().encode(RenameUserPlaylistRequest(title: title))
        let response = try await client.send(.renameUserPlaylist(id: id), body: body)
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(UserPlaylistResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func deletePlaylist(id: String) async throws {
        let response = try await client.send(.deleteUserPlaylist(id: id))
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
    }

    func attachSongs(playlistID: String, songIDs: [String]) async throws {
        let body = try JSONEncoder().encode(UserPlaylistSongIdsRequest(songIds: songIDs))
        let response = try await client.send(.attachSongsToPlaylist(playlistId: playlistID), body: body)
        // `attachSongsToPlaylist` (`userPlaylist.controller.js`) returns a
        // confirmed quirk: `401 "All songs are already in playlist"` when
        // every requested id is already attached — a real, intentional
        // response for an otherwise-successful no-op, not an auth failure.
        guard response.statusCode == 200 || response.statusCode == 401 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
    }

    func detachSongs(playlistID: String, songIDs: [String]) async throws {
        let body = try JSONEncoder().encode(UserPlaylistSongIdsRequest(songIds: songIDs))
        let response = try await client.send(.detachSongsFromPlaylist(playlistId: playlistID), body: body)
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
    }

    func fetchSongs(playlistID: String, page: Int) async throws -> UserPlaylistSongsPage {
        let response = try await client.send(.userPlaylistSongs(playlistId: playlistID, page: page))
        guard response.statusCode == 200 else {
            throw UserPlaylistRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(UserPlaylistSongsResponseDTO.self, from: response.data)
        guard let page = decoded.toDomain() else {
            throw UserPlaylistRepositoryError.missingPlaylist
        }
        return page
    }
}
