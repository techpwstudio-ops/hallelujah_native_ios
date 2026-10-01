import AVFoundation
import Observation

/// T57 — Bible-reading "Listen" feature. Generalizes Flutter's
/// `lib/river_pods/tts_player_provider.dart` (there, an AI-chat-message
/// reader only) onto a Bible passage instead — there is no dedicated TTS
/// file anywhere in `lib/services/read_service.dart` or the read feature to
/// port literally; this is the actual reference for the behavior progress.md
/// asks for. Wraps `AVSpeechSynthesizer` (native's TTS engine, vs. Dart's
/// `flutter_tts` plugin) and coordinates with `AudioEngine` so starting
/// speech pauses music and restores it afterwards — this class's own
/// "Done" bar per progress.md T57.
///
/// Scoped out (see the type's own inline notes below for why): re-pausing
/// music if the user manually starts a song *while* TTS is already
/// speaking (Dart's `_playerSub`/`_pauseForMusic`) — the Done bar only
/// requires the TTS→music direction, and reacting to the reverse needs
/// continuous `@Observable` tracking on `AudioEngine.status` that isn't
/// worth the added surface for a case the Done bar doesn't ask for.
///
/// Deliberately does not configure `AVAudioSession` itself (unlike Dart's
/// `_tts` setup, which sets an explicit `.playback`/spokenAudio category —
/// `flutter_tts` doesn't inherit the app's own session config the way
/// `AVSpeechSynthesizer` does). `AudioEngine.init` already sets the shared
/// session to `.playback` once, at composition time, well before any view
/// can reach this controller; duplicating that call here with a different
/// `mode` would risk leaving the session in that mode after speech ends,
/// since `AudioEngine.resume()` only calls `setActive(true)`, not
/// `setCategory` — it re-applies the category only on its own interruption-
/// end path. Simplest correct answer: leave the session alone.
@Observable
@MainActor
final class ReadAloudController: NSObject {
    enum Status: Equatable {
        case idle
        case loading
        case playing
        case paused
    }

    private(set) var status: Status = .idle
    /// Identifies the passage currently loaded (caller-defined — the Reader
    /// uses `"\(bookNumber)-\(chapterNumber)-\(languageName)"`) so it can
    /// tell whether tapping "Listen" again should toggle play/pause on what's
    /// already loaded or start fresh. Ports Dart's `messageId`/`isActiveFor`.
    private(set) var activeKey: String?
    private(set) var charOffset: Int = 0
    private(set) var charTotal: Int = 0
    /// Suppresses play/pause button flicker during a stop-then-respeak seek
    /// cycle — ports Dart's `isRestarting` exactly (see its own doc comment:
    /// the engine has no true seek, only stop-and-respeak-from-offset).
    private(set) var isRestarting = false

    var progress: Double {
        guard charTotal > 0 else { return 0 }
        return Double(charOffset) / Double(charTotal)
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine: AudioEngine
    private var fullText = ""
    private var voice: AVSpeechSynthesisVoice?
    /// Whether *this controller* paused the music (vs. it already being
    /// paused, or not playing at all) — only ever resume what we ourselves
    /// paused, so we never fight a user's own pause. Ports Dart's
    /// `_wasMusicPlaying`.
    private var wasMusicPlayingWhenStarted = false
    /// Bumped on every `stopCurrentUtterance()` call; `speak(from:)` stamps
    /// its own generation and a delegate callback discards itself if the
    /// generation has since moved on — guards against a cancelled
    /// utterance's straggling callback landing after a newer one already
    /// started. Ports Dart's `_pendingCancelCount`/`_seekGeneration`
    /// disambiguation.
    private var generation = 0
    private var speakingGeneration = 0
    private var currentUtteranceBaseOffset = 0
    private var settleTask: Task<Void, Never>?

    init(container: DependencyContainer = .current) {
        audioEngine = container.resolve()
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public control surface

    /// Starts reading `verses` aloud under `key`/`languageName`, or toggles
    /// play/pause if `key` is already the active passage. Joins verse text
    /// with a space so the synthesizer pauses naturally between verses —
    /// Bible verse text carries no markdown, so Dart's `_stripMarkdown` step
    /// (chat-message-only) has nothing to strip here and is skipped.
    func toggle(key: String, verses: [BibleVerse], languageName: String) {
        guard !verses.isEmpty else { return }
        if activeKey == key {
            togglePlayPause()
            return
        }
        let alreadyOwnedPause = wasMusicPlayingWhenStarted
        stopCurrentUtterance()
        activeKey = key
        fullText = verses.map(\.text).joined(separator: " ")
        charTotal = (fullText as NSString).length
        charOffset = 0
        voice = SpeechLocales.bestVoice(forLanguageName: languageName)
        // Switching directly from one passage to another while we already
        // own the music pause shouldn't resume-then-immediately-repause —
        // that would visibly flicker the mini player. Only the very first
        // passage of a "session" (or a fresh one started after a real
        // `stop()`) needs to check and pause.
        if alreadyOwnedPause {
            wasMusicPlayingWhenStarted = true
        } else {
            pauseMusicIfNeeded()
        }
        status = .loading
        speak(from: 0)
    }

    func togglePlayPause() {
        switch status {
        case .playing:
            guard synthesizer.isSpeaking else { return }
            synthesizer.pauseSpeaking(at: .word)
            status = .paused
        case .paused:
            guard synthesizer.isPaused else { return }
            synthesizer.continueSpeaking()
            status = .playing
        case .idle, .loading:
            break
        }
    }

    /// Snaps to the nearest word boundary at `fraction`, then stops and
    /// respeaks from there — `AVSpeechSynthesizer` has no true seek, only
    /// speak-from-a-substring, the same constraint Dart documents for its
    /// `flutter_tts`-based `seekToFraction`.
    func seek(toFraction fraction: Double) {
        guard activeKey != nil, charTotal > 0 else { return }
        let target = Int((Double(charTotal) * fraction).rounded())
        restart(from: wordBoundary(at: target))
    }

    /// Fully stops reading and restores music if this controller paused it.
    /// The Reader calls this when the "Listen" panel is dismissed; a plain
    /// pause (via `togglePlayPause()`) deliberately leaves music paused —
    /// only a full stop gives it back.
    func stop() {
        stopCurrentUtterance()
        resumeMusicIfNeeded()
    }

    // MARK: - Private — playback

    private func stopCurrentUtterance() {
        generation += 1
        settleTask?.cancel()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeKey = nil
        status = .idle
        charOffset = 0
        charTotal = 0
        isRestarting = false
    }

    /// Stop-then-respeak seek cycle — ports Dart's `_settleAfterStop()` 300ms
    /// delay (iOS audio-session teardown timing after `stopSpeaking`) before
    /// issuing the next utterance.
    private func restart(from offset: Int) {
        let targetGeneration = generation + 1
        generation = targetGeneration
        isRestarting = true
        charOffset = offset
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.generation == targetGeneration else { return }
            self.isRestarting = false
            self.speak(from: offset)
        }
    }

    private func speak(from offset: Int) {
        guard offset < charTotal else {
            status = .idle
            activeKey = nil
            resumeMusicIfNeeded()
            return
        }
        speakingGeneration = generation
        currentUtteranceBaseOffset = offset
        let nsText = fullText as NSString
        let remainder = nsText.substring(from: offset)
        let utterance = AVSpeechUtterance(string: remainder)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        status = .playing
    }

    private func wordBoundary(at index: Int) -> Int {
        let nsText = fullText as NSString
        let clamped = min(max(index, 0), nsText.length)
        guard clamped > 0, clamped < nsText.length else { return clamped }
        let searchRange = NSRange(location: 0, length: clamped)
        let spaceRange = nsText.rangeOfCharacter(from: .whitespaces, options: .backwards, range: searchRange)
        guard spaceRange.location != NSNotFound else { return 0 }
        return spaceRange.location + 1
    }

    // MARK: - Private — music ducking

    private func pauseMusicIfNeeded() {
        wasMusicPlayingWhenStarted = audioEngine.status == .playing
        if wasMusicPlayingWhenStarted {
            audioEngine.pause()
        }
    }

    private func resumeMusicIfNeeded() {
        guard wasMusicPlayingWhenStarted else { return }
        wasMusicPlayingWhenStarted = false
        // Only resume if music is still where we left it — iOS releasing the
        // audio session on `stopSpeaking()` can let a paused player silently
        // resume underneath on its own; don't stack a second resume on top.
        if audioEngine.status == .paused {
            audioEngine.resume()
        }
    }

    // MARK: - Private — delegate callback bodies

    // Called (hopped to the main actor) from the `nonisolated` delegate
    // methods below — `AVSpeechSynthesizerDelegate`'s methods are
    // `nonisolated` in the SDK, so a direct conformance on this `@MainActor`
    // type is a Swift 6 strict-concurrency error ("crosses into main
    // actor-isolated code"). Each delegate method stays a thin `nonisolated`
    // stub that hops back with `Task { @MainActor in ... }`.
    private func handleWillSpeak(range characterRange: NSRange) {
        guard generation == speakingGeneration else { return }
        charOffset = currentUtteranceBaseOffset + characterRange.location
    }

    private func handleDidFinish() {
        guard generation == speakingGeneration, !isRestarting else { return }
        charOffset = charTotal
        status = .idle
        activeKey = nil
        resumeMusicIfNeeded()
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.handleWillSpeak(range: characterRange)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.handleDidFinish()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Fired by our own `stopSpeaking()` calls, from both
        // `stopCurrentUtterance()` (which already reset state) and
        // `restart(from:)` (mid-flight — its own `settleTask` speaks the
        // next utterance). Either way, nothing to do here.
    }
}
