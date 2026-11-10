/// What the silent video may know about the audio, and by the shape of this type nothing more:
/// four reads and no methods. Code holding an `AudioClock` cannot stop, pause, seek or wait for the
/// audio, even by mistake.
@MainActor
protocol AudioClock {
    /// Where the audio is now. Meaningful only while `isReady` and `mediaId` is the episode being
    /// looked at.
    var positionMs: Int { get }
    /// Whether the listener has the audio playing, as opposed to paused.
    var isPlaying: Bool { get }
    /// Whether the audio is producing sound at `positionMs`. False while loading, rebuffering,
    /// finished or idle, when the position says nothing about what is heard.
    var isReady: Bool { get }
    /// The id of the item the audio has loaded: an episode's `Song.id`.
    var mediaId: String? { get }
}

/// The real clock. It reads the engine fresh on every call and caches nothing.
@MainActor
struct EngineAudioClock: AudioClock {
    let engine: AudioEngine

    var positionMs: Int { engine.currentPlaybackMs() }

    var isPlaying: Bool {
        if case .playing = engine.status { true } else { false }
    }

    var isReady: Bool {
        switch engine.status {
        case .playing, .paused: true
        case .idle, .loading, .failed: false
        }
    }

    var mediaId: String? { engine.currentSong?.id }
}
