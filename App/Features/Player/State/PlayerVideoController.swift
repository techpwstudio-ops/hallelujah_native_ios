import CoreGraphics
import Foundation
import Observation

/// Keeps one silent video with the audio, and decides when its picture may show.
///
/// It reads the audio through an `AudioClock`, which cannot command it, and drives one `VideoPlayback`
/// by the plan `VideoSync` makes. It owns no timer: whoever attached the player calls `tick()` every
/// `VideoSync.reconcileIntervalMs`. That keeps this type free of tasks, and lets a test run seconds of
/// playback in an instant.
@MainActor
@Observable
final class PlayerVideoController {
    /// The picture is the right frame and may show over the cover.
    private(set) var isShown = false
    /// The video cannot be played. Stays set until the next `attach(_:)`, so the view can say so once.
    private(set) var hasFailed = false
    /// The picture's size; zero until known.
    private(set) var videoSize: CGSize = .zero

    private let clock: any AudioClock
    private let songId: String

    // Sync state. None of it is drawn, so none of it is observed.
    @ObservationIgnored private var playback: (any VideoPlayback)?
    /// Time as the loop counts it: the sum of the periods that have gone by. Cooldowns and grace
    /// periods run on this rather than the wall clock, so a test's fake time holds them the same.
    @ObservationIgnored private var elapsedMs = 0
    @ObservationIgnored private var lastSeekAtMs: Int?
    @ObservationIgnored private var outOfSyncSinceMs: Int?

    init(clock: any AudioClock, songId: String) {
        self.clock = clock
        self.songId = songId
    }

    /// Starts following the audio with `playback`, letting go of any player held before.
    func attach(_ playback: any VideoPlayback) {
        release()
        if hasFailed { hasFailed = false }
        self.playback = playback
    }

    /// One look at both players, and whatever it takes to bring the video back to the audio. Call it
    /// every `stepMs` (the time since the last call), and once right away.
    func tick(stepMs: Int = VideoSync.reconcileIntervalMs) {
        guard let playback else { return }
        if playback.hasFailed {
            fail()
            return
        }
        // Still opening: nothing to line up yet, and no time has been counted.
        guard playback.isReady else { return }
        reconcile(playback)
        elapsedMs += stepMs
    }

    /// Lets go of the player, if there is one. Safe at any time and any number of times. Leaves
    /// `hasFailed` as it was.
    func release() {
        playback?.teardown()
        playback = nil
        elapsedMs = 0
        lastSeekAtMs = nil
        outOfSyncSinceMs = nil
        if isShown { isShown = false }
        if videoSize != .zero { videoSize = .zero }
    }

    // MARK: Private

    private func fail() {
        release()
        if !hasFailed { hasFailed = true }
    }

    private func reconcile(_ playback: any VideoPlayback) {
        if videoSize != playback.videoSize { videoSize = playback.videoSize }

        // The audio is read next to the video so the two readings are as close in time as can be.
        let audio = AudioReading(
            positionMs: clock.positionMs,
            isReady: clock.isReady && clock.mediaId == songId,
            isPlaying: clock.isPlaying
        )
        let video = VideoReading(
            positionMs: playback.positionMs,
            durationMs: playback.durationMs,
            isPlaying: playback.isPlaying,
            isBuffering: playback.isBuffering
        )
        let plan = VideoSync.plan(
            audio: audio,
            video: video,
            sinceLastSeekMs: lastSeekAtMs.map { elapsedMs - $0 }
        )

        // Decided from the readings above, before the plan is carried out: a jump about to be made
        // says nothing about the frame on screen now.
        updateShown(audio: audio, video: video)

        if let target = plan.seekToMs {
            lastSeekAtMs = elapsedMs
            playback.seek(toMs: target)
        }
        if plan.play == true {
            playback.play()
        } else if plan.play == false {
            playback.pause()
        }
    }

    private func updateShown(audio: AudioReading, video: VideoReading) {
        if audio.isReady, VideoSync.drift(audio: audio, video: video) > VideoSync.hideDriftMs {
            if outOfSyncSinceMs == nil { outOfSyncSinceMs = elapsedMs }
        } else {
            outOfSyncSinceMs = nil
        }
        let shown = VideoSync.nextShown(
            shown: isShown,
            audio: audio,
            video: video,
            outOfSyncForMs: outOfSyncSinceMs.map { elapsedMs - $0 } ?? 0
        )
        if shown != isShown { isShown = shown }
    }
}
