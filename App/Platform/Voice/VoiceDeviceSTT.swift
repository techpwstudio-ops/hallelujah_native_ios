import AVFoundation
import Foundation
import Speech

/// One recognition result from the on-device recogniser.
struct VoiceDeviceSTTResult: Sendable {
    let text: String
    /// True when the recogniser considers the utterance finished. Only a
    /// final result becomes a turn.
    let isFinal: Bool
    /// BCP-47 tag the recogniser was configured with, echoed so the server
    /// can record the language of the turn the same way the sidecar does.
    let localeId: String?
}

struct VoiceDeviceSTTUnavailable: Error {
    var message: String
}

/// T59 — ports `DeviceStt`/`SpeechToTextDeviceStt`
/// (`lib/features/voice/audio/device_stt.dart`) onto `Speech`.
///
/// ## Why this exists
///
/// The server negotiates an engine in `v.ready`. `backend` means the
/// streaming STT sidecar is live and the phone just ships PCM. `device`
/// means it is not, and this class is what makes that engine real: without
/// it, `device` mode opens the microphone and streams frames nowhere useful
/// — no backend recogniser is attached to consume them.
///
/// ## The one invariant that changes on this path
///
/// The backend path keeps the microphone open through every phase via
/// `VoiceMicCapture` streaming PCM to the socket — that is the whole point
/// of the always-on-mic rebuild. This path cannot: the platform recogniser
/// owns the input exclusively and has no echo cancellation of its own, so
/// leaving it listening while the assistant speaks makes it transcribe the
/// assistant. So this class does not run alongside `VoiceMicCapture` — the
/// controller uses one or the other, never both — and on this path
/// recognition is paused while speaking and resumed after, restarting the
/// recogniser after every final. `v.stt.device` carries only the resulting
/// TEXT to the server; no audio goes over the socket on this path at all.
///
/// This is a degraded mode and is documented as one. It is strictly better
/// than the alternative (silence), and strictly worse than the backend
/// engine, which is why the server prefers the sidecar whenever it can
/// reach it.
///
/// ## Structural note versus the Dart original
///
/// `speech_to_text` is a single plugin call that owns both the recogniser
/// and the microphone internally. `Speech`'s `SFSpeechRecognizer` does not
/// capture audio itself — callers feed it `AVAudioPCMBuffer`s — so this
/// class owns a private `AVAudioEngine` dedicated to that feed, entirely
/// separate from `AVEngineVoiceMicCapture`. This is plumbing the plugin was
/// doing under the hood, not a behavioural difference.
@MainActor
protocol VoiceDeviceSTT: AnyObject {
    var onResult: ((VoiceDeviceSTTResult) -> Void)? { get set }
    /// 0...1, for the orb. Computed locally from the same tap buffers fed
    /// to the recogniser, since `Speech` exposes no sound-level API of its
    /// own the way the Android/`speech_to_text` path did.
    var onLevelChanged: ((Double) -> Void)? { get set }
    var isListening: Bool { get }

    /// Prepares the platform recogniser. False when it is unavailable or
    /// the user refused microphone or speech-recognition permission.
    func initialize() async -> Bool
    /// Begins (or resumes) continuous recognition in `localeId`.
    func start(localeId: String?) async
    /// Stops recognition but keeps the recogniser initialised, so `start`
    /// is cheap. Used while the assistant is speaking.
    func pause() async
    /// Ends recognition for good.
    func stop() async
    func dispose()
}

@MainActor
final class SFSpeechDeviceSTT: VoiceDeviceSTT {
    /// Gap before re-arming after the platform ends a session. Restarting
    /// synchronously inside the previous task's own completion callback is
    /// rejected on iOS the same way it is on Android.
    private static let restartDelay: Duration = .milliseconds(250)

    /// Matches `VoiceLocalVAD`'s smoothing coefficient so the orb feels the
    /// same on both STT paths.
    private static let levelSmoothing: Double = 0.3

    var onResult: ((VoiceDeviceSTTResult) -> Void)?
    var onLevelChanged: ((Double) -> Void)?
    private(set) var isListening = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var initialised = false
    private var disposed = false

    /// The caller wants us listening. Distinct from `isListening`: the
    /// platform ends its session after every utterance, and this is what
    /// tells the restart loop whether to re-arm or stay quiet.
    private var wantListening = false
    private var localeId: String?
    private var restartTask: Task<Void, Never>?

    /// Guards against two overlapping arm attempts.
    private var arming = false

    private var levelFloor: Double = 1
    private var levelCeiling: Double = 0
    private var smoothedLevel: Double = 0

    func initialize() async -> Bool {
        guard !disposed else { return false }
        if initialised { return true }

        guard await requestSpeechAuthorization() else {
            return false
        }
        guard await requestMicPermission() else {
            return false
        }

        initialised = true
        return true
    }

    private func requestSpeechAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(localeId: String?) async {
        guard !disposed else { return }
        if let localeId, !localeId.isEmpty { self.localeId = localeId }

        wantListening = true
        await arm()
    }

    private func arm() async {
        guard !disposed, wantListening, !arming else { return }
        guard !isListening else { return }

        if !initialised {
            guard await initialize() else { return }
        }
        guard !disposed, wantListening else { return }

        arming = true
        defer { arming = false }

        do {
            try beginRecognition()
        } catch {
            teardownAll()
            scheduleRestart()
        }
    }

    private func beginRecognition() throws {
        let locale = Locale(identifier: localeId ?? SpeechLocales.defaultLocale)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceDeviceSTTUnavailable(message: String(localized: "No recogniser available for \(locale.identifier)."))
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            Task { @MainActor in self?.handleTap(buffer) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw VoiceDeviceSTTUnavailable(message: String(localized: "Could not start the audio engine: \(error.localizedDescription)"))
        }

        self.recognizer = recognizer
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in self?.handleTaskCallback(result: result, error: error) }
        }
        isListening = true
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard isListening else { return }
        request?.append(buffer)
        updateLevel(from: buffer)
    }

    /// Root-mean-square of the tap buffer, adaptively normalised the same
    /// way `VoiceLocalVAD` normalises its PCM16 frames. Reimplemented
    /// rather than shared: this tap runs at the engine's native Float32
    /// hardware format, not the PCM16-at-16kHz wire format `VoiceLocalVAD`
    /// expects.
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sumSquares: Double = 0
        let samples = channelData[0]
        for i in 0 ..< frameCount {
            let sample = Double(samples[i])
            sumSquares += sample * sample
        }
        let rms = (sumSquares / Double(frameCount)).squareRoot()

        if rms < levelFloor { levelFloor = rms }
        if rms > levelCeiling { levelCeiling = rms }
        let span = abs(levelCeiling - levelFloor)
        let raw = span < 0.001 ? 0.0 : (rms - levelFloor) / span
        smoothedLevel = smoothedLevel * (1 - Self.levelSmoothing) + min(max(raw, 0), 1) * Self.levelSmoothing
        onLevelChanged?(smoothedLevel)
    }

    private func handleTaskCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        guard !disposed else { return }

        if let result {
            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty || result.isFinal {
                onResult?(VoiceDeviceSTTResult(text: text, isFinal: result.isFinal, localeId: localeId))
            }
        }

        // Every recognition session ends this way eventually — with a
        // final result, or with an error when the platform closes the
        // session (a silence timeout, a route change, a dropped audio
        // unit). Continuous recognition on this path IS this restart,
        // exactly as on the Android/`speech_to_text` path.
        guard error != nil || result?.isFinal == true else { return }

        teardownAll()
        if wantListening { scheduleRestart() }
    }

    private func scheduleRestart() {
        guard !disposed, wantListening else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: Self.restartDelay)
            guard !Task.isCancelled else { return }
            await self?.arm()
        }
    }

    func pause() async {
        wantListening = false
        restartTask?.cancel()
        restartTask = nil

        isListening = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        // Deliberately not tearing down `task`/`request` here: `endAudio()`
        // lets the recogniser flush one more final result through the
        // existing callback, exactly like `stop()` on the Dart plugin —
        // "stop() delivers whatever has been recognised so far as a final,
        // and half a sentence is better than none." `handleTaskCallback`
        // finishes the teardown once that trailing final (or an error)
        // arrives; `wantListening` is already false by then, so it will
        // not be re-armed.
        request?.endAudio()
    }

    func stop() async {
        wantListening = false
        restartTask?.cancel()
        restartTask = nil
        teardownAll()
    }

    private func teardownAll() {
        isListening = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        wantListening = false
        restartTask?.cancel()
        restartTask = nil
        teardownAll()
    }
}
