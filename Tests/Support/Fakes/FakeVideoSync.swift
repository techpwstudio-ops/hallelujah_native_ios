import CoreGraphics
@testable import Hallelujah

/// An `AudioClock` a test moves by hand. It moves only while playing and ready, as real audio does.
@MainActor
final class FakeAudioClock: AudioClock {
    var positionMs = 0
    var isPlaying = false
    var isReady = true
    var mediaId: String? = "ep1"

    /// Real time passing: the audio moves on only while it is playing and ready.
    func advance(byMs ms: Int) {
        if isPlaying && isReady { positionMs += ms }
    }
}

/// A `VideoPlayback` a test drives by hand, with fake time.
///
/// It records every command. `frozen` makes it ignore `play()` (it never moves), `ignoresSeeks` makes
/// it take no notice of a jump, and `seekLatencyMs` makes a jump land only after that much fake time,
/// reading as buffering until then. `isBuffering` is "a jump is pending".
@MainActor
final class FakeVideoPlayback: VideoPlayback {
    var isReady = true
    var hasFailed = false
    var positionMs = 0
    var durationMs = 1_800_000
    var isPlaying = false
    var videoSize = CGSize(width: 320, height: 240)

    var frozen = false
    var ignoresSeeks = false
    var seekLatencyMs = 0

    private(set) var seeks: [Int] = []
    private(set) var plays = 0
    private(set) var pauses = 0
    private(set) var teardowns = 0

    private var pendingSeek: (targetMs: Int, remainingMs: Int)?

    var isBuffering: Bool { pendingSeek != nil }

    func seek(toMs ms: Int) {
        seeks.append(ms)
        if ignoresSeeks { return }
        if seekLatencyMs > 0 {
            pendingSeek = (ms, seekLatencyMs)
        } else {
            positionMs = ms
        }
    }

    func play() {
        plays += 1
        if !frozen { isPlaying = true }
    }

    func pause() {
        pauses += 1
        isPlaying = false
    }

    func teardown() {
        teardowns += 1
        isPlaying = false
    }

    /// Real time passing: a pending jump lands when its latency is up, and a playing video moves on.
    func advance(byMs ms: Int) {
        if var pending = pendingSeek {
            pending.remainingMs -= ms
            if pending.remainingMs <= 0 {
                positionMs = pending.targetMs
                pendingSeek = nil
            } else {
                pendingSeek = pending
            }
            return
        }
        if isPlaying && !frozen { positionMs += ms }
    }
}
