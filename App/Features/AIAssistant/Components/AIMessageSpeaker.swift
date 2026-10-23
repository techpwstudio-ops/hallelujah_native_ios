import AVFoundation
import Foundation
import Observation

/// Reads an AI reply aloud (device voice) — the native counterpart of Flutter's
/// `ttsPlayerProvider` (`lib/river_pods/tts_player_provider.dart`). One shared
/// instance drives both the per-message speaker button and `AITtsBar`.
@Observable
@MainActor
final class AIMessageSpeaker: NSObject {
    static let shared = AIMessageSpeaker()

    enum Status: Equatable {
        case idle
        case loading
        case playing
        case paused
    }

    private(set) var status: Status = .idle
    private(set) var activeMessageID: String?
    private(set) var charOffset: Int = 0
    private(set) var charTotal: Int = 0
    private(set) var isRestarting = false

    /// The bar is visible while audio is loaded.
    var isVisible: Bool { activeMessageID != nil }
    var isBuffering: Bool { status == .loading || isRestarting }
    var isTransportPlaying: Bool { status == .playing || isRestarting }
    var canSeek: Bool { charTotal > 0 && status != .loading }
    var progress: Double {
        guard charTotal > 0 else { return 0 }
        return min(max(Double(charOffset) / Double(charTotal), 0), 1)
    }

    func isActive(for messageID: String) -> Bool { activeMessageID == messageID }

    private let synthesizer = AVSpeechSynthesizer()
    private var fullText = ""
    private var voice: AVSpeechSynthesisVoice?
    private var generation = 0
    private var speakingGeneration = 0
    private var baseOffset = 0
    private var settleTask: Task<Void, Never>?
    /// The utterance being spoken. Delegate callbacks for any other one (a
    /// reply that was replaced, or a stop that reports late) are ignored;
    /// without this a late "finished" from the previous answer closed the
    /// bar right after the next one started, so it flickered in and out.
    private var currentUtterance: ObjectIdentifier?
    /// Keeps the song down while Emet reads (`tts_player_provider.dart`).
    private let musicHold = MusicPauseHold()
    private var isObservingMusic = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Control

    /// Starts reading `content`, or toggles play/pause when this message is already active.
    func play(messageID: String, content: String?, language: String?) {
        if activeMessageID == messageID {
            togglePlayPause()
            return
        }
        guard let content, !content.isEmpty else { return }
        stopUtterance(resumeMusic: false)
        let text = Self.stripMarkdown(content)
        guard !text.isEmpty else {
            musicHold.resumeMusic()
            return
        }
        musicHold.pauseMusic()
        observeMusic()
        activeMessageID = messageID
        fullText = text
        charTotal = (text as NSString).length
        charOffset = 0
        voice = Self.voice(forISO: language)
        status = .loading
        speak(from: 0)
    }

    func togglePlayPause() {
        switch status {
        case .playing:
            guard synthesizer.isSpeaking else { return }
            synthesizer.pauseSpeaking(at: .word)
            status = .paused
            // Emet paused: give the song back until Emet is resumed.
            musicHold.resumeMusic()
        case .paused:
            guard synthesizer.isPaused else { return }
            musicHold.pauseMusic()
            synthesizer.continueSpeaking()
            status = .playing
        case .idle, .loading:
            break
        }
    }

    func seek(toFraction fraction: Double) {
        guard activeMessageID != nil, charTotal > 0 else { return }
        let target = Int((Double(charTotal) * fraction).rounded())
        restart(from: wordBoundary(at: target))
    }

    /// Closes the bar and stops speaking.
    func dismiss() {
        stopUtterance()
    }

    // MARK: - Private

    private func stopUtterance(resumeMusic: Bool = true) {
        generation += 1
        settleTask?.cancel()
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeMessageID = nil
        status = .idle
        charOffset = 0
        charTotal = 0
        isRestarting = false
        if resumeMusic { musicHold.resumeMusic() }
    }

    /// When the user starts music while Emet is speaking, pause the reading
    /// (not close it — they keep their place), as `_playerSub` does in
    /// `tts_player_provider.dart`.
    private func observeMusic() {
        guard !isObservingMusic,
              let engine = DependencyContainer.current.resolveIfRegistered(AudioEngine.self) else { return }
        isObservingMusic = true
        withObservationTracking {
            _ = engine.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isObservingMusic = false
                // Ignore the player echoing our own pause/resume: only a
                // user pressing play should pause the reading.
                if engine.status == .playing, self.status == .playing, !self.isRestarting,
                   !self.musicHold.changedMusicRecently {
                    self.musicHold.forget()
                    self.synthesizer.pauseSpeaking(at: .word)
                    self.status = .paused
                }
                if self.activeMessageID != nil { self.observeMusic() }
            }
        }
    }

    private func restart(from offset: Int) {
        let target = generation + 1
        generation = target
        isRestarting = true
        charOffset = offset
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.generation == target else { return }
            self.isRestarting = false
            self.speak(from: offset)
        }
    }

    private func speak(from offset: Int) {
        guard offset < charTotal else {
            stopUtterance()
            return
        }
        speakingGeneration = generation
        baseOffset = offset
        let remainder = (fullText as NSString).substring(from: offset)
        let utterance = AVSpeechUtterance(string: remainder)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
        status = .playing
    }

    private func wordBoundary(at index: Int) -> Int {
        let nsText = fullText as NSString
        let clamped = min(max(index, 0), nsText.length)
        guard clamped > 0, clamped < nsText.length else { return clamped }
        let searchRange = NSRange(location: 0, length: clamped)
        let space = nsText.rangeOfCharacter(from: .whitespaces, options: .backwards, range: searchRange)
        guard space.location != NSNotFound else { return 0 }
        return space.location + 1
    }

    fileprivate func handleWillSpeak(range: NSRange, utterance: ObjectIdentifier) {
        guard utterance == currentUtterance, generation == speakingGeneration else { return }
        charOffset = baseOffset + range.location
    }

    fileprivate func handleDidFinish(utterance: ObjectIdentifier) {
        guard utterance == currentUtterance, generation == speakingGeneration, !isRestarting else { return }
        stopUtterance()
    }

    // MARK: - Helpers

    private static let localeByISO: [String: String] = [
        "en": "en-IN", "hi": "hi-IN", "te": "te-IN", "ta": "ta-IN", "kn": "kn-IN",
        "ml": "ml-IN", "bn": "bn-IN", "gu": "gu-IN", "mr": "mr-IN", "pa": "pa-IN",
        "or": "or-IN", "as": "as-IN", "ur": "ur-IN", "ar": "ar-SA", "zh": "zh-CN",
        "ja": "ja-JP", "ko": "ko-KR", "es": "es-ES", "fr": "fr-FR", "de": "de-DE",
        "pt": "pt-BR", "ru": "ru-RU", "it": "it-IT", "id": "id-ID", "th": "th-TH",
        "vi": "vi-VN",
    ]

    private static func voice(forISO iso: String?) -> AVSpeechSynthesisVoice? {
        let code = (iso ?? "en").lowercased()
        let tag = localeByISO[code] ?? code
        if let voice = AVSpeechSynthesisVoice(language: tag) { return voice }
        return AVSpeechSynthesisVoice(language: "en-IN") ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Removes markdown punctuation so it isn't read out.
    private static func stripMarkdown(_ text: String) -> String {
        var result = text
        let patterns = ["```[\\s\\S]*?```", "`", "\\*\\*", "__", "(?m)^\\s{0,3}#{1,6}\\s*", "(?m)^\\s*>\\s?", "(?m)^\\s*[-*•]\\s+"]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: "*", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AIMessageSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleWillSpeak(range: characterRange, utterance: id)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleDidFinish(utterance: id)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
