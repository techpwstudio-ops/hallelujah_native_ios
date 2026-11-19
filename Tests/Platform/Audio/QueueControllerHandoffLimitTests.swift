import Foundation
import Testing
@testable import Hallelujah

extension LiveAudioEngineTests {
/// Two creators recommend each other, and every queue ends almost at once —
/// the shape of the 2026-11-17 storm, where queues ended without playing and
/// the app handed off between two creators several times a second.
@MainActor
@Suite
struct QueueControllerHandoffLimitTests {
    @Test func automaticHandOffsStopAtTheLimitButNextStillWorks() async throws {
        let folder = try AudioFixtures.makeFolder()
        let songsA = (1...2).map { Song.fixture(id: "a-\($0)", type: "episode", duration: 1) }
        let songsB = (1...2).map { Song.fixture(id: "b-\($0)", type: "episode", duration: 1) }
        for song in songsA + songsB { try AudioFixtures.writeSilence(seconds: 0.2, for: song, in: folder) }

        let engine = AudioFixtures.makeEngine(folder: folder)
        let service = RelatedContentService(
            repository: TwoCreatorsRelated(),
            playlists: NoPlaylists(),
            creators: TwoCreatorsSongs(songs: [HandoffIDs.a: songsA, HandoffIDs.b: songsB])
        )
        let queue = QueueController(engine: engine, keyValueStore: InMemoryKeyValueStore(), relatedContent: service)
        var notices: [String] = []
        queue.onNotice = { notices.append($0) }

        await queue.play(
            songs: songsA, startIndex: 0,
            source: QueueAttribution(playerType: .creator, id: HandoffIDs.a, title: "A")
        )
        try await AudioFixtures.waitUntil(timeout: .seconds(15)) { notices.count >= QueueController.maxAutomaticHandoffs }
        // Long enough for several more hand-offs if nothing stopped them.
        try await Task.sleep(for: .seconds(4))
        #expect(notices.count == QueueController.maxAutomaticHandoffs)

        // Stopped on the last song of the last queue. The listener's Next is
        // never limited: it hands off once more.
        #expect(queue.queue?.currentIndex == (queue.queue?.songs.count ?? 0) - 1)
        await queue.skipToNext()
        try await AudioFixtures.waitUntil(timeout: .seconds(10)) { notices.count == QueueController.maxAutomaticHandoffs + 1 }
        try await Task.sleep(for: .seconds(2))
        #expect(notices.count == QueueController.maxAutomaticHandoffs + 1)
    }
}
}

private enum HandoffIDs {
    static let a = "creator-a"
    static let b = "creator-b"
}

private struct TwoCreatorsRelated: RelatedContentRepository {
    func fetchRelated(songId: String, excludeId: String?, limit: Int) async throws -> RelatedContent {
        let items = [HandoffIDs.a, HandoffIDs.b]
            .filter { $0 != excludeId }
            .map { RelatedItem(kind: .creator, id: $0, title: $0, reason: nil, image: nil, imageVariants: nil) }
        return RelatedContent(kind: .creator, items: items)
    }
}

private struct TwoCreatorsSongs: CreatorRepository {
    let songs: [String: [Song]]
    func fetchSongs(creatorId: String, type: HomeContentType, page: Int) async throws -> Paginated<Song> {
        .page(songs[creatorId] ?? [])
    }
    func fetchCreator(id: String) async throws -> Creator { throw CancellationError() }
    func fetchPlaylists(creatorId: String, type: HomeContentType, page: Int) async throws -> Paginated<Playlist> { .page([]) }
    func follow(creatorId: String) async throws -> Creator? { nil }
    func unfollow(creatorId: String) async throws -> Creator? { nil }
    func unfollow(creatorIds: [String]) async throws {}
    func fetchAllCreators(page: Int) async throws -> Paginated<Creator> { .page([]) }
    func setFollowedCreators(ids: [String], replacingExisting: Bool) async throws {}
}

private struct NoPlaylists: PlaylistRepository {
    func fetchSongs(playlistId: String, owner: PlaylistOwner, page: Int) async throws -> Paginated<Song> { .page([]) }
}
