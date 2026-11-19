import Foundation
import Testing
@testable import Hallelujah

/// Drives a real `AudioEngine` (`AVQueuePlayer`) over local files. A file of
/// junk bytes fails to load the same way a refused stream does:
/// `AVQueuePlayer` skips each failed item on its own until it holds nothing.
extension LiveAudioEngineTests {
@MainActor
@Suite
struct AudioEngineQueueEndTests {
    @Test func aQueueWhoseItemsAllFailIsNotReportedAsFinished() async throws {
        let folder = try AudioFixtures.makeFolder()
        let songs = (1...3).map { Song.fixture(id: "episode-\($0)", type: "episode") }
        for song in songs { try AudioFixtures.writeJunk(for: song, in: folder) }
        let engine = AudioFixtures.makeEngine(folder: folder)
        let exhausted = AudioFixtures.Counter()
        engine.onQueueExhausted = { exhausted.count += 1 }

        await engine.play(queue: songs, startAt: 0)
        try await AudioFixtures.waitUntil { if case .failed = engine.status { true } else { false } }
        // Room for a late "queue ran out" report to land.
        try await Task.sleep(for: .milliseconds(500))

        #expect(exhausted.count == 0)
        if case .failed = engine.status {} else {
            Issue.record("expected .failed, got \(engine.status)")
        }
    }

    @Test func aQueueThatPlaysToItsEndIsReportedAsFinished() async throws {
        let folder = try AudioFixtures.makeFolder()
        let songs = (1...2).map { Song.fixture(id: "episode-\($0)", type: "episode", duration: 1) }
        for song in songs { try AudioFixtures.writeSilence(seconds: 0.3, for: song, in: folder) }
        let engine = AudioFixtures.makeEngine(folder: folder)
        let exhausted = AudioFixtures.Counter()
        engine.onQueueExhausted = { exhausted.count += 1 }

        await engine.play(queue: songs, startAt: 0)
        try await AudioFixtures.waitUntil(timeout: .seconds(10)) { exhausted.count > 0 }

        #expect(exhausted.count == 1)
        #expect(engine.currentSong?.id == "episode-2")
    }
}
}
