import Foundation

/// Pauses the music player while another audio source (Emet reading a reply,
/// the voice conversation) speaks, and gives the song back afterwards only if
/// this hold was what paused it. Ports the `_pauseMusicIfNeeded` /
/// `_resumeMusicIfNeeded` pair in `tts_player_provider.dart` and
/// `_pauseMusicForLoop` / `_resumeMusicIfWePaused` in
/// `voice_conversation_provider.dart`.
///
/// The app's speech and `AudioEngine` share one audio session, so iOS mixes
/// them instead of interrupting either: without an explicit pause the song
/// plays straight over Emet.
@MainActor
final class MusicPauseHold {
    private(set) var pausedMusic = false

    private var engine: AudioEngine? {
        DependencyContainer.current.resolveIfRegistered(AudioEngine.self)
    }

    /// Pauses music if it is playing (or about to). Safe to call repeatedly.
    func pauseMusic() {
        guard let engine else { return }
        switch engine.status {
        case .playing, .loading:
            pausedMusic = true
            engine.pause()
        case .idle, .paused, .failed:
            break
        }
    }

    /// Resumes music only if `pauseMusic()` paused it and nobody has touched
    /// the player since.
    func resumeMusic() {
        guard pausedMusic else { return }
        pausedMusic = false
        guard let engine, engine.status == .paused else { return }
        engine.resume()
    }

    /// The user took the song back (started/resumed it themselves): it is
    /// theirs now, ours neither to resume nor re-pause.
    func forget() {
        pausedMusic = false
    }
}
