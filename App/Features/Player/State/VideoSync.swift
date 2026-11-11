import Foundation

/// What the planner knows about the audio. The audio is the clock; nothing in this file can
/// command it.
struct AudioReading: Sendable, Equatable {
    var positionMs: Int
    /// False while the audio is loading, rebuffering or finished: its position says nothing then.
    var isReady: Bool
    /// The listener's intent: playing, as opposed to paused.
    var isPlaying: Bool
}

/// What the planner knows about the silent video.
struct VideoReading: Sendable, Equatable {
    var positionMs: Int
    /// Zero while unknown.
    var durationMs: Int
    var isPlaying: Bool
    var isBuffering: Bool
}

/// What the video has to do to stay with the audio.
struct VideoSyncPlan: Sendable, Equatable {
    /// Where to jump the video to. `nil` leaves its position alone.
    var seekToMs: Int?
    /// `true` to play it, `false` to pause it, `nil` to leave it as it is.
    var play: Bool?

    var isNoop: Bool { seekToMs == nil && play == nil }
}

enum VideoFit: Sendable, Equatable {
    case cover
    case contain
}

/// Decides what the silent video does to follow the audio.
///
/// THE AUDIO IS THE CLOCK AND THE VIDEO IS THE FOLLOWER, and that only ever goes one way. Nothing
/// here, and nothing that carries out a plan, can stop, pause, seek or wait for the audio: a video
/// that is late, stalled or failed costs a frame, never a word.
///
/// Pure on purpose: the caller feeds it what it just read from the two players and does what comes
/// back, so every rule is a plain unit test rather than something to watch happen on a phone.
enum VideoSync {
    /// Drift allowed while both are running before the video is pulled back.
    static let playingToleranceMs = 300
    /// The same while the audio is paused: the picture is a still, so it is held closer.
    static let pausedToleranceMs = 120
    /// Least time between two corrective jumps while playing. A jump makes the player rebuffer and
    /// report a position nowhere near its target; correcting again then turns one slip into a stutter.
    static let playingSeekCooldownMs = 1_500
    /// Least time between two jumps while paused: short, so a scrub keeps the frame up with the thumb.
    static let pausedSeekCooldownMs = 250
    /// Within this of the video's end the video is no longer asked to play.
    static let tailGuardMs = 150
    /// A corrective jump while playing lands this far ahead of the audio, because it takes a moment
    /// to land and the audio does not wait. Must stay below `playingToleranceMs`.
    static let seekLeadMs = 200
    /// Drift past which a picture that is showing no longer belongs to what is heard.
    static let hideDriftMs = 1_500
    /// How long the drift must stay past `hideDriftMs` before the cover returns.
    static let hideGraceMs = 1_000
    /// How close a video's aspect must be to the box's before the video fills the box.
    static let fillTolerance = 0.06
    /// Period of the sync loop once the picture is up.
    static let reconcileIntervalMs = 250
    /// Period of the sync loop while the listener waits for the picture: faster, so it comes up the
    /// moment it is ready rather than up to a quarter second later. Runs only for that wait.
    static let fastReconcileIntervalMs = 50
    /// How long the picture may take before the loading spinner appears at all. On an ordinary
    /// connection it is up well inside this, so the switch reads as instant: the cover crossfades
    /// into the video with no spinner flashing up and away.
    static let spinnerDelayMs = 1_000

    /// What the video has to do right now to stay with the audio. `sinceLastSeekMs` is how long ago
    /// the video was last jumped, `nil` if never.
    static func plan(audio: AudioReading, video: VideoReading, sinceLastSeekMs: Int?) -> VideoSyncPlan {
        guard audio.isReady else {
            return VideoSyncPlan(seekToMs: nil, play: video.isPlaying ? false : nil)
        }
        let target = targetMs(audio: audio, video: video)
        let playing = wantsPlaying(audio: audio, video: video)
        let cooldown = playing ? playingSeekCooldownMs : pausedSeekCooldownMs
        let cooledDown = sinceLastSeekMs.map { $0 >= cooldown } ?? true
        let drifted = abs(video.positionMs - target) > tolerance(playing: playing)
        // A jump while the player is rebuffering restarts the rebuffer.
        let seeks = drifted && cooledDown && !(playing && video.isBuffering)
        return VideoSyncPlan(
            seekToMs: seeks ? landingMs(target: target, playing: playing, video: video) : nil,
            play: playDecision(playing: playing, video: video)
        )
    }

    /// How far the video is from where it should be, in either direction.
    static func drift(audio: AudioReading, video: VideoReading) -> Int {
        abs(video.positionMs - targetMs(audio: audio, video: video))
    }

    /// Whether the picture is on screen over the cover. It comes up only once it is the right frame
    /// (in step and not buffering) and stays until it has been wrong for a while, so a skip or a
    /// scrub does not flash the cover. `outOfSyncForMs` is how long the drift has been past
    /// `hideDriftMs`, zero when it is not.
    static func nextShown(shown: Bool, audio: AudioReading, video: VideoReading, outOfSyncForMs: Int) -> Bool {
        guard audio.isReady else { return shown }
        let off = drift(audio: audio, video: video)
        if shown {
            return !(off > hideDriftMs && outOfSyncForMs >= hideGraceMs)
        }
        let playing = wantsPlaying(audio: audio, video: video)
        return !video.isBuffering && off <= tolerance(playing: playing)
    }

    /// Fill the box when the video is the box's shape to within a few percent, fit it otherwise.
    static func fit(videoAspect: Double, boxAspect: Double) -> VideoFit {
        guard videoAspect > 0, boxAspect > 0 else { return .contain }
        return abs(videoAspect / boxAspect - 1) <= fillTolerance ? .cover : .contain
    }

    // MARK: - Pieces

    /// Where the video should be for the audio to be at `audio.positionMs`: the same place, except
    /// that a video shorter than the audio holds on its last frame.
    private static func targetMs(audio: AudioReading, video: VideoReading) -> Int {
        video.durationMs > 0 && audio.positionMs > video.durationMs ? video.durationMs : audio.positionMs
    }

    /// Within the tail guard of the video's end. A video whose length is not known yet cannot be run
    /// off the end of, so it is never near it.
    private static func isNearEnd(audio: AudioReading, video: VideoReading) -> Bool {
        video.durationMs > 0 && audio.positionMs >= video.durationMs - tailGuardMs
    }

    /// Whether the video should be playing: the audio is, and the video has not run out.
    private static func wantsPlaying(audio: AudioReading, video: VideoReading) -> Bool {
        audio.isPlaying && !isNearEnd(audio: audio, video: video)
    }

    private static func tolerance(playing: Bool) -> Int {
        playing ? playingToleranceMs : pausedToleranceMs
    }

    /// Where a corrective jump lands: a little ahead of the audio while it runs, never past the point
    /// where playing would restart the video, and exactly on the audio while it is paused.
    private static func landingMs(target: Int, playing: Bool, video: VideoReading) -> Int {
        guard playing else { return target }
        let ahead = target + seekLeadMs
        return video.durationMs > 0 ? min(ahead, video.durationMs - tailGuardMs) : ahead
    }

    /// A buffering video has been told to play already, so it is not told again.
    private static func playDecision(playing: Bool, video: VideoReading) -> Bool? {
        if playing && !video.isPlaying && !video.isBuffering { return true }
        if !playing && video.isPlaying { return false }
        return nil
    }
}
