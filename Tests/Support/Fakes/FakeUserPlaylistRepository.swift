import Foundation
@testable import Hallelujah

/// A scriptable `UserPlaylistRepository`; only the follow/visibility calls are
/// scriptable, everything else throws.
final class FakeUserPlaylistRepository: UserPlaylistRepository, @unchecked Sendable {
    struct Failure: Error {}

    var visibilityResult: Result<UserPlaylist, Error> = .failure(Failure())
    var followResult: Result<String, Error> = .failure(Failure())
    private(set) var followCalls: [String] = []
    private(set) var visibilityCalls: [String] = []

    static func playlist(id: String = "p1", visibility: String?) -> UserPlaylist {
        UserPlaylist(
            id: id, title: "Mine", description: nil, image: nil, imageVariants: nil,
            visibility: visibility, songsCount: nil, duration: nil, ownerUserID: "u1", createdAt: nil
        )
    }

    func fetchPlaylists(page: Int) async throws -> Paginated<UserPlaylist> { throw Failure() }
    func fetchPlaylist(id: String) async throws -> UserPlaylist { throw Failure() }
    func createPlaylist(title: String, songID: String?) async throws -> UserPlaylist { throw Failure() }
    func renamePlaylist(id: String, title: String) async throws -> UserPlaylist { throw Failure() }
    func deletePlaylist(id: String) async throws { throw Failure() }
    func attachSongs(playlistID: String, songIDs: [String]) async throws { throw Failure() }
    func detachSongs(playlistID: String, songIDs: [String]) async throws { throw Failure() }
    func fetchSongs(playlistID: String, page: Int) async throws -> UserPlaylistSongsPage { throw Failure() }

    func toggleVisibility(id: String) async throws -> UserPlaylist {
        visibilityCalls.append(id)
        return try visibilityResult.get()
    }

    func toggleFollow(id: String) async throws -> String {
        followCalls.append(id)
        return try followResult.get()
    }
}
