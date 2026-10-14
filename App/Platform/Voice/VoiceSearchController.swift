import AVFoundation
import Foundation
import Observation
import Speech

/// Ports the session logic of `VoiceSearchButton`
/// (`lib/widgets/search/voice_search_button.dart`): dictation through the
/// platform recogniser (`SFSpeechRecognizer`), no server round-trip.
///
/// Nothing is requested until the first `toggle()` — the permission prompts
/// must not appear merely because a search screen opened. Partial results
/// stream to `onResult`; 3s of silence or 30s total ends the session; the
/// locale is the device's when it isn't English, otherwise `en-IN` when the
/// device has it (Indian-accented English transcribes better there).
@MainActor
@Observable
final class VoiceSearchController {
    enum Failure: Equatable {
        /// Permission permanently refused — offer Settings.
        case permissionDenied
        case unavailable
        case notHeard
        case failed
    }

    private(set) var isListening = false
    /// 0...1 input level for the halo.
    private(set) var level: Double = 0
    private(set) var failure: Failure?

    /// `(text, isFinal)` for every recognised phrase.
    var onResult: ((String, Bool) -> Void)?
    var onListeningChanged: ((Bool) -> Void)?

    private static let pauseFor: Duration = .seconds(3)
    private static let listenFor: Duration = .seconds(30)

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var pauseTimer: Task<Void, Never>?
    private var ceilingTimer: Task<Void, Never>?
    private var heardAnything = false
    private let audio: AudioEngine
    private var pausedMusic = false
    private let logger = AppLogger(category: .content)

    init(audio: AudioEngine = DependencyContainer.current.resolve()) {
        self.audio = audio
    }

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func cancel() {
        tearDown()
        setListening(false)
    }

    // MARK: Session

    private func start() async {
        failure = nil
        guard await authorize() else { return }
        guard let recognizer = makeRecognizer(), recognizer.isAvailable else {
            failure = .unavailable
            return
        }
        self.recognizer = recognizer
        do {
            try beginCapture(recognizer: recognizer)
        } catch {
            logger.warning("voice-search: start failed: \(error)")
            tearDown()
            failure = .failed
            return
        }
        pauseMusicIfPlaying()
        heardAnything = false
        setListening(true)
        armCeiling()
    }

    /// `stop` flushes what was heard as a final result (cancel would drop it).
    func stop() {
        request?.endAudio()
        task?.finish()
        finishSession()
    }

    private func beginCapture(recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, request] buffer, _ in
            request.append(buffer)
            let level = Self.normalisedLevel(buffer)
            Task { @MainActor [weak self] in self?.level = level }
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text, !text.isEmpty {
            heardAnything = true
            onResult?(text, isFinal)
            armPause()
        }
        if isFinal {
            finishSession()
        } else if failed {
            let heard = heardAnything
            finishSession()
            if !heard { failure = .notHeard }
        }
    }

    private func finishSession() {
        tearDown()
        setListening(false)
    }

    private func tearDown() {
        pauseTimer?.cancel(); pauseTimer = nil
        ceilingTimer?.cancel(); ceilingTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func setListening(_ value: Bool) {
        guard isListening != value else { return }
        isListening = value
        if !value { resumeMusicIfWePaused() }
        onListeningChanged?(value)
    }

    // MARK: Timers

    private func armPause() {
        pauseTimer?.cancel()
        pauseTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.pauseFor)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func armCeiling() {
        ceilingTimer?.cancel()
        ceilingTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.listenFor)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    // MARK: Permission / locale

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        if speech == .authorized && mic { return true }
        if speech == .restricted { failure = .unavailable } else { failure = .permissionDenied }
        return false
    }

    /// Non-English devices transcribe in the device language; English devices
    /// prefer `en-IN` (`kDefaultSpeechLocale`), then `en-US`.
    private func makeRecognizer() -> SFSpeechRecognizer? {
        let system = Locale.current
        if system.language.languageCode?.identifier != "en", let r = SFSpeechRecognizer(locale: system) {
            return r
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()
    }

    // MARK: Playback

    private func pauseMusicIfPlaying() {
        guard audio.status == .playing else { return }
        pausedMusic = true
        audio.pause()
    }

    private func resumeMusicIfWePaused() {
        guard pausedMusic else { return }
        pausedMusic = false
        audio.resume()
    }

    nonisolated private static func normalisedLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = (sum / Float(count)).squareRoot()
        return Double(min(max(rms * 6, 0), 1))
    }
}
