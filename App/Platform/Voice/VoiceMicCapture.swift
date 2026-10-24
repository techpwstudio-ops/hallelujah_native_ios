import AVFoundation
import Foundation

/// T59 — audio format for the whole voice pipeline (ports
/// `VoiceAudioFormat`, `lib/features/voice/audio/mic_capture.dart`). Every
/// layer — the sidecar, the VAD, the wire framing — assumes exactly this,
/// so it is stated once.
enum VoiceAudioFormat {
    static let sampleRate: Double = 16000
    static let channels: AVAudioChannelCount = 1
    static let bytesPerSample = 2 // PCM16

    /// One wire frame is 100ms: 16000 x 0.1 x 2 bytes.
    static let frameBytes = 3200

    /// What the input tap is asked to hand back per callback — 20ms. Small
    /// buffers keep capture latency down; `VoiceMicCapture` re-frames them
    /// up to `frameBytes` itself.
    static let captureBufferBytes = 640

    static let frameDuration: Duration = .milliseconds(100)

    static var format: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
    }
}

/// Thrown by `start()` when the user will not grant the microphone.
struct VoiceMicPermissionDenied: Error {
    var message = String(localized: "Microphone permission denied.")
}

/// Thrown when the engine itself refuses to start — device busy, another
/// app holding the input, an audio session that never came back.
struct VoiceMicUnavailable: Error {
    var message: String
}

/// A microphone that yields fixed-size PCM16LE frames. Ports the
/// `MicCapture` abstract class.
@MainActor
protocol VoiceMicCapture: AnyObject {
    /// Exactly `VoiceAudioFormat.frameBytes` per callback. Never a partial
    /// frame.
    var onFrame: ((Data) -> Void)? { get set }
    /// Fires when the PLATFORM ended capture without being asked to — a
    /// route switch, another app taking the input, an audio unit restart.
    ///
    /// This exists because the failure it reports is invisible otherwise:
    /// frames simply stop arriving, the socket stays healthy, and the UI
    /// sits in `listening` with a dead microphone. Whoever owns this
    /// instance must treat it as "reopen me", not as "the conversation is
    /// over".
    var onEnded: (() -> Void)? { get set }
    var isRunning: Bool { get }
    func start() async throws
    func stop() async
    func dispose() async
}

/// `VoiceMicCapture` over `AVAudioEngine`.
///
/// The single most important property of this class: the `AVAudioEngine`
/// is built once in the initializer and never rebuilt. Re-creating it
/// across turns, reconnects or errors is what produces the classic bugs —
/// a dead tap after the second turn, and iOS handing back an audio session
/// the previous instance has not finished releasing. Only `start()` and
/// `stop()` are ever called on it.
///
/// Deliberately does not touch `AVAudioSession` category/mode at all —
/// `VoiceAudioSessionOwner` is the single claimant of the session
/// (`.playAndRecord` / `.voiceChat`, which engages Apple's Voice-Processing
/// I/O AEC), matching Dart's `_recorder.ios?.manageAudioSession(false)`
/// intent: this class must not fight the session owner over configuration.
@MainActor
final class AVEngineVoiceMicCapture: VoiceMicCapture {
    var onFrame: ((Data) -> Void)?
    var onEnded: (() -> Void)?

    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    /// Leftover bytes from the last tap callback that did not complete a
    /// frame. Carried into the next callback.
    private var carry = Data()

    private var disposed = false
    /// The in-flight `start()`, so `stop()` can wait for it instead of
    /// racing it.
    private var startTask: Task<Void, Error>?
    private var startTaskID: UUID?
    /// Set by `stop()` while a `start()` is still in flight. `start()`
    /// checks it after every await and unwinds rather than leaving the
    /// engine running behind a caller that already believes the
    /// microphone is closed.
    private var stopRequested = false

    private var configurationObserver: NSObjectProtocol?

    /// Opens the microphone.
    ///
    /// Every await in here is a window in which the caller may change its
    /// mind — the permission prompt can sit on screen for as long as the
    /// user takes to answer it. `stop()` arriving inside that window must
    /// not be a silent no-op, or the engine stays hot for the rest of the
    /// process with its owner believing the microphone was closed. Hence
    /// `stopRequested` and the checks after each await.
    func start() async throws {
        if disposed { throw VoiceMicUnavailable(message: "used after dispose") }

        if let inFlight = startTask {
            return try await inFlight.value
        }
        if isRunning { return }

        stopRequested = false
        let task = Task { try await self.performStart() }
        let taskID = UUID()
        startTask = task
        startTaskID = taskID
        defer { if startTaskID == taskID { startTask = nil; startTaskID = nil } }
        try await task.value
    }

    private func performStart() async throws {
        let granted = await requestPermission()
        if disposed { return }
        guard granted else { throw VoiceMicPermissionDenied() }
        if stopRequested { return }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioConverter(from: hardwareFormat, to: VoiceAudioFormat.format) else {
            throw VoiceMicUnavailable(message: String(localized: "Could not build a PCM16 16kHz mono converter."))
        }
        converter = targetFormat

        carry.removeAll(keepingCapacity: true)

        let bufferFrameCount = AVAudioFrameCount(hardwareFormat.sampleRate * 0.02) // ~20ms
        // `@Sendable`: the tap runs on the audio render thread, and a
        // `@MainActor`-inferred block would trap Swift 6's isolation check.
        inputNode.installTap(onBus: 0, bufferSize: bufferFrameCount, format: hardwareFormat) { @Sendable [weak self] buffer, _ in
            nonisolated(unsafe) let buffer = buffer
            Task { @MainActor in self?.handleTap(buffer) }
        }

        observeConfigurationChanges()

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            converter = nil
            throw VoiceMicUnavailable(message: String(localized: "Could not open the microphone: \(error.localizedDescription)"))
        }

        // The engine IS running now, whatever the caller has since
        // decided. Unwinding it here is the only place that can: stop()
        // has already returned, or is waiting on this task.
        if disposed || stopRequested {
            hardStop()
            return
        }

        isRunning = true
    }

    /// The SDK's async overload — a hand-written completion closure here
    /// would be `@MainActor`-inferred and trap on TCC's background queue.
    private func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Re-frames variable-size tap buffers into exact 3200-byte frames.
    ///
    /// The engine honours `bufferFrameCount` only loosely — the OS hands
    /// over whatever size its own I/O cycle produced. The sidecar's
    /// whisper front-end and the VAD's RMS window both assume fixed
    /// framing, so the carry buffer is not a nicety: without it every
    /// downstream millisecond figure drifts.
    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard isRunning || startTask != nil else { return }
        guard let converter else { return }

        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * VoiceAudioFormat.sampleRate / buffer.format.sampleRate
        ) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: VoiceAudioFormat.format, frameCapacity: outputFrameCapacity) else { return }

        var error: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, let channelData = outputBuffer.int16ChannelData else { return }

        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0 else { return }
        let chunk = Data(bytes: channelData[0], count: frameCount * VoiceAudioFormat.bytesPerSample)
        onChunk(chunk)
    }

    private func onChunk(_ chunk: Data) {
        guard !chunk.isEmpty else { return }

        carry.append(chunk)
        while carry.count >= VoiceAudioFormat.frameBytes {
            let frame = carry.prefix(VoiceAudioFormat.frameBytes)
            onFrame?(Data(frame))
            carry.removeFirst(VoiceAudioFormat.frameBytes)
        }
    }

    /// AVAudioEngine has no direct equivalent of a plugin stream's "platform
    /// closed this on its own" callback; a configuration-change
    /// notification followed by the engine no longer running is the
    /// closest available signal (a route change, another process seizing
    /// the input, or the I/O unit restarting under the hood) — the
    /// analogue of `RecordMicCapture`'s `onDone` handler.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
    }

    private func handleConfigurationChange() {
        guard isRunning, !engine.isRunning else { return }
        isRunning = false
        onEnded?()
    }

    func stop() async {
        // Claim the intent FIRST, so a start still inside `performStart()`
        // sees it and unwinds itself.
        stopRequested = true

        if let starting = startTask {
            _ = try? await starting.value
        }

        hardStop()
    }

    /// Unconditional teardown. Safe to call when nothing is running.
    private func hardStop() {
        isRunning = false

        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        converter = nil

        // A partial frame from the turn just ended must not be prepended
        // to the first frame of the next one.
        carry.removeAll(keepingCapacity: true)
    }

    func dispose() async {
        if disposed { return }
        disposed = true
        await stop()
    }
}
