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

    @discardableResult
    func follow(creatorId: String) async throws -> Creator {
        let body = try JSONEncoder().encode(FollowCreatorsRequest(detach: false, ids: [creatorId]))
        let response = try await client.send(.followCreators, body: body)
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(CreatorListResponseDTO.self, from: response.data)
        guard let match = decoded.data.first(where: { $0.id == creatorId }) ?? decoded.data.first else {
            throw CreatorRepositoryError.creatorNotFound
        }
        // `attachCreators` trusts the decoded response as-is — no
        // client-side correction, unlike `unfollow` below.
        return match.toDomain()
    }

    @discardableResult
    func unfollow(creatorId: String) async throws -> Creator {
        let body = try JSONEncoder().encode(UnfollowCreatorsRequest(ids: [creatorId]))
        let response = try await client.send(.unfollowCreators, body: body)
        guard response.statusCode == 200 else {
            throw CreatorRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(CreatorListResponseDTO.self, from: response.data)
        guard let match = decoded.data.first(where: { $0.id == creatorId }) ?? decoded.data.first else {
            throw CreatorRepositoryError.creatorNotFound
        }
        // `detachCreator` (`lib/blocs/favourite/bloc.dart`) does NOT trust
        // the response for these two fields — after decoding it, it
        // unconditionally forces `isFavourite = false` and decrements
        // `followersCount` locally, implying the un-follow response's own
        // `followers`/`followersCount` don't reliably reflect the
        // just-applied change. Matched here exactly, same reconstruction
        // Dart does (its own comment gives no further reasoning — ported
        // as observed behavior, not "fixed").
        let decodedCreator = match.toDomain()
        return Creator(
            creatorId: decodedCreator.creatorId,
            name: decodedCreator.name,
            displayName: decodedCreator.displayName,
            image: decodedCreator.image,
            imageVariants: decodedCreator.imageVariants,
            bio: decodedCreator.bio,
            email: decodedCreator.email,
            mobile: decodedCreator.mobile,
            username: decodedCreator.username,
            link: decodedCreator.link,
            band: decodedCreator.band,
            isActive: decodedCreator.isActive,
            createdAt: decodedCreator.createdAt,
            updatedAt: decodedCreator.updatedAt,
            followersCount: decodedCreator.followersCount.map { $0 - 1 },
            songsCount: decodedCreator.songsCount,
            episodeCount: decodedCreator.episodeCount,
            musicCount: decodedCreator.musicCount,
            playlistsCount: decodedCreator.playlistsCount,
            albumsCount: decodedCreator.albumsCount,
            seasonsCount: decodedCreator.seasonsCount,
            isFollowing: false
        )
    }
}
