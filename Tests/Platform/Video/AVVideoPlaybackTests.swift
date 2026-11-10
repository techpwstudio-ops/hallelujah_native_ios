import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Hallelujah

/// Where the 40-second silent test clip is, if there is one: H.264 High, 320x240, yuv420p, 25 fps,
/// 40.000 s, a keyframe every second, video only. It is made with
///
///     ffmpeg -f lavfi -i testsrc=size=320x240:rate=25 -t 40 -g 25 -pix_fmt yuv420p -c:v libx264 -an \
///         -movflags +faststart clip.mp4
///
/// The clip is not in the repository (about 300 KB, and nobody has decided to bundle it). Point
/// `TEST_RUNNER_HALLELUJAH_TEST_CLIP` at it to run these tests (`xcodebuild` passes the variable to
/// the test process without the `TEST_RUNNER_` prefix); without it they are skipped, not failed.
private enum TestClip {
    private final class BundleToken {}

    static let url: URL? = {
        if let path = ProcessInfo.processInfo.environment["HALLELUJAH_TEST_CLIP"],
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return Bundle(for: BundleToken.self).url(forResource: "silent-clip", withExtension: "mp4")
    }()
}

/// `AVVideoPlayback` on a real file. Time here is real time, so these poll rather than sleep for a
/// fixed while: every wait is "check every 10 ms, give up after 5 s".
@MainActor
@Suite(.serialized, .enabled(if: TestClip.url != nil, "needs the 40 s silent test clip; see TestClip"))
struct AVVideoPlaybackTests {
    private func makePlayback() throws -> AVVideoPlayback {
        AVVideoPlayback(url: try #require(TestClip.url), headers: [:])
    }

    /// Polls `condition` every 10 ms for up to 5 s. True if it came true in time.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func openedPlayback() async throws -> AVVideoPlayback {
        let playback = try makePlayback()
        let ready = await waitUntil { playback.isReady }
        try #require(ready, "the clip never became ready")
        return playback
    }

    @Test func openingGivesASilentReadyPlayerWithTheClipsShape() async throws {
        let playback = try makePlayback()
        defer { playback.teardown() }
        #expect(!playback.isPlaying)
        #expect(!playback.isBuffering)

        #expect(await waitUntil { playback.isReady })
        #expect(!playback.hasFailed)
        #expect(abs(playback.durationMs - 40_000) <= 100)
        #expect(playback.videoSize == CGSize(width: 320, height: 240))
        #expect(playback.player.isMuted)
        #expect(playback.player.volume == 0)
        #expect(!playback.isPlaying, "not playing before play()")
        #expect(!playback.isBuffering, "not buffering at rest")
    }

    @Test func aJumpReadsAsBufferingAtOnceAndLandsExactly() async throws {
        let playback = try await openedPlayback()
        defer { playback.teardown() }

        playback.seek(toMs: 12_345)
        #expect(playback.isBuffering)
        #expect(await waitUntil { !playback.isBuffering })
        #expect(playback.positionMs == 12_345)
    }

    @Test func playAndPauseTakeEffectAtOnceAndPauseHolds() async throws {
        let playback = try await openedPlayback()
        defer { playback.teardown() }
        playback.seek(toMs: 12_345)
        #expect(await waitUntil { !playback.isBuffering })

        playback.play()
        #expect(playback.isPlaying)
        #expect(await waitUntil { playback.positionMs > 12_745 })

        playback.pause()
        #expect(!playback.isPlaying)
        // `pause()` sets the rate at once, but the clock can still creep a millisecond or two while the
        // render pipeline stops. What must hold is that it stays put after that: let it settle, then compare.
        try await Task.sleep(for: .milliseconds(150))
        let held = playback.positionMs
        try await Task.sleep(for: .milliseconds(300))
        #expect(playback.positionMs == held)
    }

    @Test func aJumpWhilePlayingLandsAndKeepsPlaying() async throws {
        let playback = try await openedPlayback()
        defer { playback.teardown() }
        playback.play()
        #expect(await waitUntil { playback.positionMs > 200 })

        playback.seek(toMs: 30_000)
        #expect(playback.isBuffering)
        #expect(await waitUntil { !playback.isBuffering })
        #expect((30_000...30_799).contains(playback.positionMs), "landed at \(playback.positionMs)")
        #expect(playback.isPlaying)
    }

    @Test func twoDifferentQuickJumpsBothReportBack() async throws {
        let playback = try await openedPlayback()
        defer { playback.teardown() }

        playback.seek(toMs: 1_000)
        playback.seek(toMs: 2_000)
        #expect(playback.seeksInFlight == 2)
        #expect(await waitUntil { !playback.isBuffering })
        #expect(await waitUntil { playback.seeksInFlight == 0 })
        #expect(abs(playback.positionMs - 2_000) <= 800, "ended at \(playback.positionMs)")
    }

    @Test func theSameJumpAskedAgainIsNotRestartedUntilItHasLanded() async throws {
        let playback = try await openedPlayback()
        defer { playback.teardown() }

        for _ in 0..<3 { playback.seek(toMs: 7_000) }
        #expect(playback.seeksInFlight == 1)
        #expect(await waitUntil { !playback.isBuffering })
        #expect(playback.positionMs == 7_000)

        playback.seek(toMs: 7_000)
        #expect(playback.seeksInFlight == 1, "once landed, the same time is a new jump")
        #expect(await waitUntil { !playback.isBuffering })
        #expect(playback.positionMs == 7_000)
    }

    @Test func teardownLetsGoOfEverythingAndMakesLaterCallsNoops() async throws {
        let playback = try await openedPlayback()
        playback.seek(toMs: 5_000)
        #expect(await waitUntil { !playback.isBuffering })

        playback.teardown()
        playback.teardown()
        #expect(!playback.isReady)
        #expect(!playback.isPlaying)
        #expect(!playback.isBuffering)
        #expect(!playback.hasFailed)
        #expect(playback.positionMs == 0)

        playback.seek(toMs: 9_000)
        playback.play()
        playback.pause()
        #expect(!playback.isPlaying)
        #expect(!playback.isBuffering)
        #expect(playback.seeksInFlight == 0, "a call after teardown starts no jump")
    }

    @Test func aMissingFileFailsAndIsNeverReady() async {
        let playback = AVVideoPlayback(url: URL(fileURLWithPath: "/nonexistent/none.mp4"), headers: [:])
        defer { playback.teardown() }
        #expect(await waitUntil { playback.hasFailed })
        #expect(!playback.isReady)
    }
}
