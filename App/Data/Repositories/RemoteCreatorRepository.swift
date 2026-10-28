import Foundation

enum CreatorRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
    /// The follow/unfollow response's `data` array didn't include a row for
    /// the id just sent — shouldn't happen for a single-id request, but
    /// there's no compiler-checked way to assert that against a live server.
    case creatorNotFound
}

final class RemoteCreatorRepository: CreatorRepository {
    private let client: HTTPClient
    private let logger = AppLogger(category: .content)

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchCreator(id: String) async throws -> Creator {
        let response = try await client.send(.creatorDetail(id: id))
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(CreatorDetailResponseDTO.self, from: response.data)
        return decoded.data.toDomain()
    }

    func fetchSongs(creatorId: String, type: HomeContentType, page: Int) async throws -> Paginated<Song> {
        let response = try await client.send(.creatorSongs(id: creatorId, type: type, page: page))
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(CreatorSongsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func fetchPlaylists(creatorId: String, type: HomeContentType, page: Int) async throws -> Paginated<Playlist> {
        let response = try await client.send(.creatorPlaylists(id: creatorId, type: type, page: page))
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(CreatorPlaylistsResponseDTO.self, from: response.data)
        return decoded.toDomain()
    }

    func fetchAllCreators(page: Int) async throws -> Paginated<Creator> {
        let response = try await client.send(.allCreators(page: page))
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder().decode(FavoriteCreatorsResponseDTO.self, from: response.data).toDomain()
    }

    func setFollowedCreators(ids: [String], replacingExisting: Bool) async throws {
        let body = try JSONEncoder().encode(FollowCreatorsRequest(detach: replacingExisting, ids: ids))
        let response = try await client.send(.followCreators, body: body)
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        await CreatorFollowStore.shared.record(isFollowing: true, creatorIDs: ids)
    }

    /// Success is the 200. The response's `data` is a list of creator rows
    /// (Dart writes every one of them into Realm and never assumes which is
    /// which); it is not guaranteed to hold the creator just sent, and after
    /// an un-follow it usually doesn't. Only a row whose id matches is
    /// returned, never "the first row", which used to swap a different
    /// artist onto the screen or fail an un-follow that had succeeded.
    @discardableResult
    func follow(creatorId: String) async throws -> Creator? {
        let body = try JSONEncoder().encode(FollowCreatorsRequest(detach: false, ids: [creatorId]))
        let response = try await client.send(.followCreators, body: body)
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        await CreatorFollowStore.shared.record(isFollowing: true, creatorIDs: [creatorId])
        return Self.row(for: creatorId, in: response.data)
    }

    @discardableResult
    func unfollow(creatorId: String) async throws -> Creator? {
        try await unfollow(creatorIds: [creatorId])
        return nil
    }

    func unfollow(creatorIds: [String]) async throws {
        guard !creatorIds.isEmpty else { return }
        let body = try JSONEncoder().encode(UnfollowCreatorsRequest(ids: creatorIds))
        let response = try await client.send(.unfollowCreators, body: body)
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        await CreatorFollowStore.shared.record(isFollowing: false, creatorIDs: creatorIds)
    }

    private static func row(for creatorId: String, in data: Data) -> Creator? {
        guard let decoded = try? JSONDecoder().decode(CreatorListResponseDTO.self, from: data) else { return nil }
        return decoded.data.first(where: { $0.id == creatorId })?.toDomain()
    }
}
