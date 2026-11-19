import AVFoundation
import Foundation
import Testing
@testable import Hallelujah

/// The simulator can't kill its media server, so these post the same
/// notification iOS posts after it restarted, against a real `AVQueuePlayer`.
extension LiveAudioEngineTests {
@MainActor
@Suite
struct AudioEnginePlayerRecoveryTests {
    private func playing(_ engine: AudioEngine) -> Bool {
        if case .playing = engine.status { true } else { false }
    }

    @Test func mediaServicesResetReplacesThePlayerAndResumesWhereItWas() async throws {
        let folder = try AudioFixtures.makeFolder()
        let songs = (1...2).map { Song.fixture(id: "episode-\($0)", type: "episode", duration: 30) }
        for song in songs { try AudioFixtures.writeSilence(seconds: 30, for: song, in: folder) }
        let engine = AudioFixtures.makeEngine(folder: folder)
        let songChanges = AudioFixtures.Counter()
        let exhausted = AudioFixtures.Counter()
        engine.onSongChanged = { _ in songChanges.count += 1 }
        engine.onQueueExhausted = { exhausted.count += 1 }

        await engine.play(queue: songs, startAt: 0)
        try await AudioFixtures.waitUntil { playing(engine) && engine.currentPosition >= 2 }
        let generationBefore = engine.playerGeneration
        let positionBefore = engine.currentPosition
        let songChangesBefore = songChanges.count

        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await AudioFixtures.waitUntil { engine.playerGeneration == generationBefore + 1 }
        // Sampled throughout the rebuild: the playhead must never drop back.
        var lowest = engine.currentPosition
        try await AudioFixtures.waitUntil {
            lowest = min(lowest, engine.currentPosition)
            return playing(engine) && engine.currentPosition > positionBefore + 0.5
        }

        #expect(engine.currentSong?.id == "episode-1")
        #expect(lowest >= positionBefore - 0.3)
        // Same song: no new analytics session, no ad-pacing tick, no hand-off.
        #expect(songChanges.count == songChangesBefore)
        #expect(exhausted.count == 0)
    }

    @Test func aPausedSongStaysPausedAtItsPosition() async throws {
        let folder = try AudioFixtures.makeFolder()
        let song = Song.fixture(id: "episode-1", type: "episode", duration: 30)
        try AudioFixtures.writeSilence(seconds: 30, for: song, in: folder)
        let engine = AudioFixtures.makeEngine(folder: folder)

        await engine.play(queue: [song], startAt: 0)
        try await AudioFixtures.waitUntil { playing(engine) && engine.currentPosition >= 2 }
        engine.pause()
        try await AudioFixtures.waitUntil { engine.status == .paused }
        let positionBefore = engine.currentPosition
        let generationBefore = engine.playerGeneration

        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await AudioFixtures.waitUntil { engine.playerGeneration == generationBefore + 1 }
        try await Task.sleep(for: .seconds(2))

        #expect(engine.status == .paused)
        #expect(abs(engine.currentPosition - positionBefore) < 0.6)
        engine.resume()
        try await AudioFixtures.waitUntil { playing(engine) && engine.currentPosition > positionBefore + 0.5 }
    }

    @Test func aSongThatKeepsKillingThePlayerIsLeftPaused() async throws {
        let folder = try AudioFixtures.makeFolder()
        let song = Song.fixture(id: "episode-1", type: "episode", duration: 30)
        try AudioFixtures.writeSilence(seconds: 30, for: song, in: folder)
        let engine = AudioFixtures.makeEngine(folder: folder)

        await engine.play(queue: [song], startAt: 0)
        try await AudioFixtures.waitUntil { playing(engine) }
        for round in 1...AudioEngine.maxAutomaticRecoveries {
            let generation = engine.playerGeneration
            NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
            try await AudioFixtures.waitUntil { engine.playerGeneration == generation + 1 }
            try await AudioFixtures.waitUntil { playing(engine) }
            #expect(playing(engine), "round \(round) should resume")
        }

        let generation = engine.playerGeneration
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await AudioFixtures.waitUntil { engine.playerGeneration == generation + 1 }
        try await Task.sleep(for: .milliseconds(800))

        #expect(engine.status == .paused)
        #expect(engine.currentSong?.id == "episode-1")
    }

    @Test func aResetWithNothingLoadedOnlyReplacesThePlayer() async throws {
        let engine = AudioFixtures.makeEngine(folder: try AudioFixtures.makeFolder())
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await AudioFixtures.waitUntil { engine.playerGeneration == 1 }
        #expect(engine.currentSong == nil)
        #expect(engine.status == .idle)
    }

    @Test func automaticResumeIsLimitedPerSong() {
        let limit = AudioEngine.maxAutomaticRecoveries
        #expect(AudioEngine.allowsAutomaticResume(songID: "a", recentRecoveries: []))
        #expect(AudioEngine.allowsAutomaticResume(songID: "a", recentRecoveries: Array(repeating: "a", count: limit - 1)))
        #expect(!AudioEngine.allowsAutomaticResume(songID: "a", recentRecoveries: Array(repeating: "a", count: limit)))
        #expect(AudioEngine.allowsAutomaticResume(songID: "b", recentRecoveries: Array(repeating: "a", count: limit)))
    }
}
}
