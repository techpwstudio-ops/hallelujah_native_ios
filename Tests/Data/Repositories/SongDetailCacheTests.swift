import Foundation
import Testing
@testable import Hallelujah

private actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

/// Counts fetches and answers after a short delay, so concurrent callers overlap.
private struct CountingSongRepository: SongRepository {
    let counter: CallCounter
    let song: Song

    func fetchSong(id: String) async throws -> Song {
        await counter.increment()
        try await Task.sleep(for: .milliseconds(30))
        return song
    }

    func reportSong(id: String, message: String) async throws {}
}

private struct FixedClock: ClockProviding {
    let date: Date

    func now() -> Date { date }
}

struct SongDetailCacheTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func concurrentRequestsForOneSongShareOneFetch() async throws {
        let counter = CallCounter()
        let cache = SongDetailCache(
            repository: CountingSongRepository(counter: counter, song: .fixture(id: "e1", type: "episode")),
            clock: FixedClock(date: now)
        )

        async let first = cache.song(id: "e1")
        async let second = cache.song(id: "e1")
        let (firstSong, secondSong) = try await (first, second)

        #expect(firstSong.id == "e1")
        #expect(secondSong.id == "e1")
        #expect(await counter.count == 1)
    }

    @Test func aFreshEntryIsServedWithoutAnotherFetch() async throws {
        let counter = CallCounter()
        let cache = SongDetailCache(
            repository: CountingSongRepository(counter: counter, song: .fixture(id: "e1")),
            clock: FixedClock(date: now)
        )

        _ = try await cache.song(id: "e1")
        _ = try await cache.song(id: "e1")

        #expect(await counter.count == 1)
    }

    @Test func forceRefreshFetchesAgain() async throws {
        let counter = CallCounter()
        let cache = SongDetailCache(
            repository: CountingSongRepository(counter: counter, song: .fixture(id: "e1")),
            clock: FixedClock(date: now)
        )

        _ = try await cache.song(id: "e1")
        _ = try await cache.song(id: "e1", forceRefresh: true)

        #expect(await counter.count == 2)
    }
}
