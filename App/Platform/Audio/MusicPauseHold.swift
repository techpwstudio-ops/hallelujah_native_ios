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
    /// When this hold last paused or resumed the player. The player reports
    /// the new state a moment later, and an observer must not mistake that
    /// echo for the user pressing play themselves.
    private var lastChange: ContinuousClock.Instant?

    private var lastResume: ContinuousClock.Instant?

    private var resumedRecently: Bool {
        guard let lastResume else { return false }
        return ContinuousClock.now - lastResume < .milliseconds(1500)
    }

    /// True for a short while after `pauseMusic()`/`resumeMusic()` acted.
    var changedMusicRecently: Bool {
        guard let lastChange else { return false }
        return ContinuousClock.now - lastChange < .milliseconds(1500)
    }

    private var engine: AudioEngine? {
        DependencyContainer.current.resolveIfRegistered(AudioEngine.self)
    }

    /// Pauses music if it is playing (or about to). Safe to call repeatedly.
    func pauseMusic() {
        guard let engine else { return }
        switch engine.status {
        case .playing, .loading:
            pausedMusic = true
            lastChange = .now
            lastResume = nil
            engine.pause()
        case .paused where resumedRecently:
            // We just asked it to resume and the player hasn't reported
            // playing yet: it is about to play, so pause it again.
            pausedMusic = true
            lastChange = .now
            lastResume = nil
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
        // Our own pause may not have been reported yet (still `.playing`);
        // resuming then is harmless and keeps the song from staying paused.
        guard let engine, engine.status == .paused || changedMusicRecently else { return }
        lastChange = .now
        lastResume = .now
        engine.resume()
    }

    /// The user took the song back (started/resumed it themselves): it is
    /// theirs now, ours neither to resume nor re-pause.
    func forget() {
        pausedMusic = false
    }
}
