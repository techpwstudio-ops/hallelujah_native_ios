import Foundation
import UIKit

/// T59 — ports `VoiceController` (`lib/features/voice/voice_controller.dart`,
/// 1577 lines). The orchestrator for one spoken conversation: wires
/// `VoiceMicCapture`, `VoiceRealtimeChannel`, `VoiceSpeechQueue`,
/// `VoiceLocalVAD`, `VoiceDeviceSTT` and `VoiceAudioSessionOwner` together
/// and drives `VoicePhase` through `voiceTransition(from:signal:)`.
///
/// ## The microphone invariant
///
/// `mic`/`deviceStt` are constructed once by the caller and never rebuilt for
/// the life of this controller. Capture is opened in exactly one place
/// (`openCapture()`, only ever called after a `v.ready` — see
/// `handleReady(_:)`) and closed in exactly one place (`applyPhase(_:)`,
/// when the phase lands on `.idle`/`.error`). Every other method that
/// touches capture — `restartCapture`, `switchEngine`, the interruption
/// handlers — goes through `openCapture()`/`closeCapture()`, never the
/// underlying `mic`/`deviceStt` directly. This is the single invariant the
/// whole file is built to protect; see `VoiceMicCapture`'s own doc comment
/// for why re-creating the engine across turns is the bug this avoids.
///
/// ## Why an `@Observable` struct instead of a Combine/Riverpod-style store
///
/// `state` is this controller's entire public surface for the UI — ports
/// Dart's `StateNotifier<VoiceState>`. Every field the overlay/screen reads
/// lives on it; there is no second source of truth.
@MainActor
@Observable
final class VoiceController {
    // MARK: - Tunables — ported verbatim from `voice_controller.dart`.

    private static let bargeDebounce: Duration = .milliseconds(220)
    /// Ignore local VAD onset for this long after the speech queue starts
    /// talking — a blanket safety margin against the assistant's own voice
    /// re-triggering barge-in, kept even though the backend engine's
    /// `.voiceChat` session already has hardware AEC.
    private static let bargeSuppression: Duration = .milliseconds(500)
    private static let levelEpsilon: Double = 0.02
    private static let bargeLevelFloor: Double = 0.05
    private static let drainGrace: Duration = .milliseconds(350)
    /// Wire frames arrive every 100ms; three missed in a row means the
    /// engine died silently.
    private static let frameSilenceTimeout: Duration = .seconds(3)
    private static let frameWatchdogTick: Duration = .seconds(1)
    private static let maxCaptureRestarts = 5
    /// Android sends no gain event after a permanent `AUDIOFOCUS_LOSS`; iOS
    /// is better-behaved but this poll is kept for parity and as a backstop.
    private static let interruptionRetryInterval: Duration = .seconds(3)
    private static let maxInterruptionRetries = 10
    /// `v.cancelled` is not guaranteed — the server may already have moved
    /// past the turn. An uncleared watermark would mute the assistant for
    /// the rest of the session (seq is monotonic), which is a far worse
    /// failure than the double-speak this watermark exists to prevent, so
    /// it always expires.
    private static let bargeWatermarkTTL: Duration = .seconds(2)
    /// Backstop for a `v.hello` that is never answered.
    private static let readyTimeout: Duration = .seconds(8)
    /// Backstop for `.transcribing`/`.thinking`, the two phases with no
    /// local exit of their own.
    private static let turnTimeout: Duration = .seconds(30)
    /// Dead in production (the server always reaches its sidecar in
    /// practice) but kept structurally, matching the Dart flag of the same
    /// name, so a server-side outage degrades to the device engine instead
    /// of going silent.
    private static let allowDeviceSttFallback = false

    // MARK: - Published state

    private(set) var state = VoiceState()

    // MARK: - Collaborators

    private let mic: VoiceMicCapture
    private let channel: VoiceRealtimeChannel
    private let speech: VoiceSpeechQueue
    private let vad: VoiceLocalVAD
    private let deviceStt: VoiceDeviceSTT
    private let audioSession: VoiceAudioSessionOwner
    private let logger = AppLogger(category: .realtime)

    // MARK: - Session/engine state

    private var engine: VoiceEngine = .backend
    private var isDeviceEngine: Bool { engine == .device }
    private var micOpen = false
    private var disposed = false
    /// Bumped on every `start()`; every await inside it re-checks `stale(_:)`
    /// so a superseded start can't clobber a newer one.
    private var generation = 0
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    // MARK: - Turn state

    private var vadSpeaking = false
    private var queueSpeaking = false
    private var replyDone = false
    private var lastSentenceSeq = 0
    private var bargeWatermark: Int?
    private var bargeSuppressedUntil: Date?

    // MARK: - Capture health

    private var lastFrameAt: Date = .distantPast
    private var captureRestarts = 0
    private var restartingCapture = false
    private var micSuspendedByInterruption = false
    private var interruptionRetryCount = 0

    // MARK: - Timers

    private var bargeTimerTask: Task<Void, Never>?
    private var drainTimerTask: Task<Void, Never>?
    private var turnTimerTask: Task<Void, Never>?
    private var watermarkTimerTask: Task<Void, Never>?
    private var readyWatchdogTask: Task<Void, Never>?
    private var frameWatchdogTask: Task<Void, Never>?
    private var interruptionRetryTask: Task<Void, Never>?

    private var lifecycleObserver: NSObjectProtocol?

    // MARK: - Init

    /// Designated initializer — mirrors the Dart constructor's shape
    /// (`mic`/`channel`/`speech`/`vad`/`deviceStt`/`audioSession` all
    /// injected) so the whole controller can be driven by fakes in a test
    /// target.
    init(
        mic: VoiceMicCapture,
        channel: VoiceRealtimeChannel,
        speech: VoiceSpeechQueue,
        vad: VoiceLocalVAD,
        deviceStt: VoiceDeviceSTT,
        audioSession: VoiceAudioSessionOwner
    ) {
        self.mic = mic
        self.channel = channel
        self.speech = speech
        self.vad = vad
        self.deviceStt = deviceStt
        self.audioSession = audioSession

        subscribe()
        observeLifecycle()
    }

    /// Production convenience initializer, matching this codebase's
    /// `init(container: DependencyContainer = .current)` DI convention
    /// (e.g. `ReaderViewModel`, `HomeFeedViewModel`). `Session`/
    /// `AppConfiguration` are the only pieces `SocketIOVoiceChannel` needs
    /// that live in the container; every other collaborator here has no
    /// shared state to resolve and is built directly, the same way
    /// `ReaderViewModel.init` builds its own `ReaderPreferencesStore`/
    /// `ReaderPositionStore` inline.
    convenience init(container: DependencyContainer = .current) {
        let session: Session = container.resolve()
        let configuration: AppConfiguration = container.resolve()
        self.init(
            mic: AVEngineVoiceMicCapture(),
            channel: SocketIOVoiceChannel(session: session, configuration: configuration),
            speech: VoiceSpeechQueue(),
            vad: VoiceLocalVAD(),
            deviceStt: SFSpeechDeviceSTT(),
            audioSession: VoiceAudioSessionOwner.shared
        )
    }

    deinit {
        if let lifecycleObserver {
            NotificationCenter.default.removeObserver(lifecycleObserver)
        }
    }

    private func subscribe() {
        mic.onFrame = { [weak self] frame in self?.onFrame(frame) }
        mic.onEnded = { [weak self] in self?.onMicEnded() }
        channel.onEvent = { [weak self] event in self?.onServerEvent(event) }
        channel.onStatusChange = { [weak self] status in self?.onStatus(status) }
        vad.onSpeakingChanged = { [weak self] speaking in self?.onVadSpeaking(speaking) }
        speech.onSpeakingChanged = { [weak self] speaking in self?.onQueueSpeaking(speaking) }
        deviceStt.onResult = { [weak self] result in self?.onDeviceResult(result) }
        deviceStt.onLevelChanged = { [weak self] level in self?.onDeviceLevel(level) }
        audioSession.onInterruption = { [weak self] interruption in self?.onInterruption(interruption) }
    }

    private func unsubscribe() {
        mic.onFrame = nil
        mic.onEnded = nil
        channel.onEvent = nil
        channel.onStatusChange = nil
        vad.onSpeakingChanged = nil
        speech.onSpeakingChanged = nil
        deviceStt.onResult = nil
        deviceStt.onLevelChanged = nil
        audioSession.onInterruption = nil
    }

    /// Native stand-in for Dart's `WidgetsBindingObserver.didChangeAppLifecycleState`
    /// (`.paused`/`.hidden`/`.detached` → `stop()`). `didEnterBackgroundNotification`
    /// is the closest single native signal for "the app is no longer able to
    /// keep this conversation going" without reaching into `AppShellView`'s
    /// own scene-phase plumbing.
    private func observeLifecycle() {
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidEnterBackground() }
        }
    }

    private func handleDidEnterBackground() {
        guard state.phase != .idle else { return }
        stop()
    }

    // MARK: - Lifecycle: start/stop/dispose

    /// Begins a conversation. A no-op if one is already live; joins an
    /// in-flight `start()` rather than racing it.
    func start(conversationID: String? = nil, ttsLocale: String? = nil) {
        guard !disposed else { return }
        guard startTask == nil else { return }
        guard !state.isActive else { return }

        startTask = Task { [weak self] in
            await self?.startAfterTeardown(conversationID: conversationID, ttsLocale: ttsLocale)
            self?.startTask = nil
        }
    }

    /// `dispose()` schedules a detached `stop()` and a re-entrant `start()`
    /// (leaving and re-entering the voice screen in the same frame) is a
    /// real race in the Dart original — waiting out any in-flight `stop()`
    /// before proceeding is what keeps a fast leave-then-return from
    /// starting a second session on top of a teardown still in progress.
    private func startAfterTeardown(conversationID: String?, ttsLocale: String?) async {
        if let stopTask {
            await stopTask.value
        }
        guard !disposed else { return }
        guard state.phase == .idle || state.phase == .error else { return }

        await performStart(conversationID: conversationID, ttsLocale: ttsLocale)
    }

    private func performStart(conversationID: String?, ttsLocale: String?) async {
        generation += 1
        let myGeneration = generation
        engine = .backend
        captureRestarts = 0
        resetTurn()
        fire(.started)

        do {
            try await audioSession.acquireForConversation()
            guard !stale(myGeneration) else { return }

            speech.prewarm()
            guard !stale(myGeneration) else { return }

            await channel.connect(conversationID: conversationID, ttsLocale: ttsLocale)
        } catch {
            guard !stale(myGeneration) else { return }
            failFatal(code: "start_failed", message: "Could not start the conversation.")
        }
    }

    /// A no-op if already idle; joins an in-flight `stop()`.
    func stop() {
        guard !disposed else { return }
        guard stopTask == nil else { return }

        stopTask = Task { [weak self] in
            await self?.performStop()
            self?.stopTask = nil
        }
    }

    private func performStop() async {
        generation += 1
        let myGeneration = generation
        cancelTimers()
        // Fires first, synchronously — closes the mic via `applyPhase`'s
        // side effect before any of the awaits below have a chance to run.
        fire(.stopped)

        await speech.stopAll()
        channel.close()
        await audioSession.release()

        vad.reset()
        resetTurn()

        guard !stale(myGeneration) else { return }
        state = VoiceState()
    }

    /// Ports `dispose()`. Teardown of the owned collaborators is
    /// deliberately fire-and-forget (`_teardownDetached()` in the Dart
    /// original): a `deinit`-adjacent call site has nothing left to await
    /// onto.
    func dispose() {
        guard !disposed else { return }
        disposed = true

        if let lifecycleObserver {
            NotificationCenter.default.removeObserver(lifecycleObserver)
            self.lifecycleObserver = nil
        }
        cancelTimers()
        startTask?.cancel()
        stopTask?.cancel()
        unsubscribe()

        speech.dispose()
        deviceStt.dispose()

        Task { [mic, channel, audioSession] in
            await mic.dispose()
            channel.close()
            await audioSession.release()
        }
    }

    private func stale(_ generationAtStart: Int) -> Bool {
        disposed || generation != generationAtStart
    }

    // MARK: - Microphone open/close

    /// The only place capture opens. Reached from exactly one call site:
    /// the tail of `handleReady(_:)`.
    private func openCapture() async {
        guard !micOpen, !disposed else { return }

        if isDeviceEngine {
            let ready = await deviceStt.initialize()
            guard !disposed else { return }
            guard ready else {
                failFatal(code: VoiceErrorCode.sttUnavailable, message: "Speech recognition is not available on this device.")
                return
            }
            await deviceStt.start(localeId: state.sttLocale)
            micOpen = true
        } else {
            do {
                try await mic.start()
            } catch {
                micOpen = false
                failFatal(code: "mic_failed", message: "Microphone unavailable.")
                return
            }
            micOpen = true
            lastFrameAt = Date()
            startFrameWatchdog()
        }
    }

    /// Always stops BOTH `mic` and `deviceStt`, regardless of which engine
    /// is current — the engine can change mid-session (`switchEngine(_:)`),
    /// and a capture left running on the other path is exactly the kind of
    /// silent bug the single-open-single-close invariant exists to prevent.
    private func closeCapture() async {
        micOpen = false
        stopFrameWatchdog()
        await mic.stop()
        await deviceStt.stop()
    }

    /// Used when the server downgrades to the device engine mid-session
    /// (`v.error{code: stt_unavailable}`, non-fatal).
    private func switchEngine(_ newEngine: VoiceEngine) async {
        guard micOpen, state.isActive, engine != newEngine else { return }
        await closeCapture()
        engine = newEngine
        await openCapture()
    }

    // MARK: - Frame watchdog

    private func startFrameWatchdog() {
        stopFrameWatchdog()
        frameWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frameWatchdogTick)
                guard !Task.isCancelled else { return }
                self?.checkFrameWatchdog()
            }
        }
    }

    private func stopFrameWatchdog() {
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil
    }

    private func checkFrameWatchdog() {
        guard micOpen, !isDeviceEngine, !micSuspendedByInterruption else { return }
        guard Date().timeIntervalSince(lastFrameAt) >= Self.frameSilenceTimeout.timeInterval else { return }
        Task { [weak self] in await self?.restartCapture(reason: "no frames for 3s") }
    }

    private func restartCapture(reason: String) async {
        guard !restartingCapture else { return }
        restartingCapture = true
        defer { restartingCapture = false }

        captureRestarts += 1
        logger.warning("Restarting voice capture (\(reason)), attempt \(self.captureRestarts).")

        if captureRestarts > Self.maxCaptureRestarts {
            failFatal(code: "mic_lost", message: "Lost the microphone. Please try again.")
            return
        }

        await closeCapture()
        guard !disposed, state.isActive else { return }
        await openCapture()
    }

    private func onMicEnded() {
        guard micOpen, !isDeviceEngine else { return }
        Task { [weak self] in await self?.restartCapture(reason: "capture ended unexpectedly") }
    }

    // MARK: - Frames (backend engine)

    private func onFrame(_ frame: Data) {
        lastFrameAt = Date()
        if captureRestarts != 0 { captureRestarts = 0 }

        vad.feed(frame)
        channel.sendAudio(frame)

        let newLevel = vad.level
        if abs(newLevel - state.level) >= Self.levelEpsilon {
            state.level = newLevel
        }
    }

    // MARK: - Device STT (fallback engine)

    /// `!queueSpeaking` is the tail-of-pause suppression: the device path
    /// has no AEC, so leaving it live while the assistant talks would
    /// transcribe the assistant back into the conversation.
    private func onDeviceResult(_ result: VoiceDeviceSTTResult) {
        guard isDeviceEngine, !queueSpeaking else { return }

        if !result.isFinal {
            state.partialTranscript = result.text
            fire(.sttPartial)
            touchTurnWatchdog()
            return
        }

        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Sent up rather than processed locally so both engines drive the
        // phase machine through exactly one path — the server echoes this
        // back as `v.stt.final`.
        channel.sendDeviceTranscript(
            text: trimmed,
            language: result.localeId.flatMap { SpeechLocales.iso(ofLocale: $0) },
            ms: 0
        )
    }

    private func onDeviceLevel(_ level: Double) {
        guard isDeviceEngine else { return }
        if abs(level - state.level) >= Self.levelEpsilon {
            state.level = level
        }
    }

    // MARK: - Local VAD / barge-in

    private func onVadSpeaking(_ speaking: Bool) {
        vadSpeaking = speaking
        if speaking {
            fire(.vadOnset)
            armBarge()
        } else {
            bargeTimerTask?.cancel()
            bargeTimerTask = nil
            fire(.vadOffset)
        }
    }

    private func armBarge() {
        guard state.phase == .speaking else { return }
        if let suppressedUntil = bargeSuppressedUntil, Date() < suppressedUntil { return }

        bargeTimerTask?.cancel()
        bargeTimerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.bargeDebounce)
            guard !Task.isCancelled else { return }
            self?.handleBargeTimerFired()
        }
    }

    private func handleBargeTimerFired() {
        guard state.phase == .speaking, vadSpeaking, vad.level >= Self.bargeLevelFloor else { return }
        interrupt()
    }

    /// Only valid while the assistant is speaking. `fromSeq` is read from
    /// `speech.currentSeq` BEFORE `stopAll()` runs — `stopAll()` clears it,
    /// so this is the one moment that value is available. That read is the
    /// real flush boundary the server is told about.
    func interrupt() {
        guard state.phase == .speaking else { return }

        let fromSeq = speech.currentSeq ?? (lastSentenceSeq + 1)
        setBargeWatermark(fromSeq)
        Task { [speech] in await speech.stopAll() }
        channel.barge(seq: fromSeq)

        replyDone = false
        drainTimerTask?.cancel()
        drainTimerTask = nil

        fire(.barge)
        state.replyText = ""
        state.partialTranscript = ""
    }

    /// An explicit cancel (e.g. the user tapping "stop"), distinct from
    /// barge-in: `fromSeq` has no `+1`, since there is no sentence the
    /// device is mid-word through the way there is during a live interrupt.
    func cancelReply(reason: String) {
        let fromSeq = speech.currentSeq ?? lastSentenceSeq
        setBargeWatermark(fromSeq)
        channel.cancel(reason: reason, seq: fromSeq)
        Task { [speech] in await speech.stopAll() }

        replyDone = false
        drainTimerTask?.cancel()
        drainTimerTask = nil
    }

    private func setBargeWatermark(_ seq: Int) {
        bargeWatermark = seq
        watermarkTimerTask?.cancel()
        watermarkTimerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.bargeWatermarkTTL)
            guard !Task.isCancelled else { return }
            self?.bargeWatermark = nil
        }
    }

    private func clearBargeWatermark() {
        bargeWatermark = nil
        watermarkTimerTask?.cancel()
        watermarkTimerTask = nil
    }

    // MARK: - Speech queue integration

    private func onQueueSpeaking(_ speaking: Bool) {
        queueSpeaking = speaking

        // The cost of the degraded no-AEC device path: recognition has to
        // step aside while the assistant talks, then restart. The backend
        // engine keeps the mic open throughout regardless.
        if isDeviceEngine, micOpen {
            if speaking {
                Task { [deviceStt] in await deviceStt.pause() }
            } else {
                let locale = state.sttLocale
                Task { [deviceStt] in await deviceStt.start(localeId: locale) }
            }
        }

        if speaking {
            bargeSuppressedUntil = Date().addingTimeInterval(Self.bargeSuppression.timeInterval)
        } else if replyDone {
            finishTurn()
        }
    }

    /// Handles an empty or instantly-cancelled reply that never reported
    /// speaking at all: if the queue isn't speaking right now, arm a short
    /// grace period and finish the turn if it's still quiet and `replyDone`
    /// once that elapses.
    private func maybeFinishTurn() {
        guard !speech.isSpeaking else { return }
        drainTimerTask?.cancel()
        drainTimerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.drainGrace)
            guard !Task.isCancelled else { return }
            self?.handleDrainGraceElapsed()
        }
    }

    private func handleDrainGraceElapsed() {
        guard !speech.isSpeaking, replyDone else { return }
        finishTurn()
    }

    private func finishTurn() {
        replyDone = false
        drainTimerTask?.cancel()
        drainTimerTask = nil
        fire(.replyDone)
        state.replyText = ""
        state.partialTranscript = ""
    }

    // MARK: - Server events

    private func onServerEvent(_ event: VoiceServerEvent) {
        switch event {
        case let .ready(payload):
            handleReady(payload)
        case .ack:
            // Liveness only — deliberately not a transition-table signal.
            break
        case .speechStart:
            state.partialTranscript = ""
            state.transcript = ""
            state.notice = nil
            fire(.speechStart)
        case let .sttPartial(payload):
            state.partialTranscript = payload.text
            fire(.sttPartial)
            touchTurnWatchdog()
        case let .sttFinal(payload):
            state.transcript = payload.text
            state.partialTranscript = ""
            state.replyText = ""
            if let language = payload.language { state.sttLocale = language }
            fire(.sttFinal)
        case let .replyDelta(payload):
            state.replyText += payload.text
            fire(.replyDelta)
            // A long reply's `thinking -> thinking` self-transition doesn't
            // re-trigger `applyPhase`, so the turn watchdog needs an
            // explicit re-arm here.
            touchTurnWatchdog()
        case let .replySentence(payload):
            handleReplySentence(payload)
        case .replyDone:
            replyDone = true
            maybeFinishTurn()
        case let .localeChanged(payload):
            handleLocaleChanged(payload)
        case let .cancelled(payload):
            handleCancelled(payload)
        case let .error(payload):
            handleError(payload)
        }
    }

    private func handleReady(_ payload: VoiceReadyPayload) {
        // A new server session restarts sentence-seq numbering.
        Task { [speech] in await speech.stopAll() }
        lastSentenceSeq = 0
        clearBargeWatermark()
        readyWatchdogTask?.cancel()
        readyWatchdogTask = nil

        engine = payload.engine ?? .backend
        if let conversationId = payload.conversationId { state.conversationID = conversationId }
        if let sttLocale = payload.sttLocale { state.sttLocale = sttLocale }
        if let ttsLocale = payload.ttsLocale { state.ttsLocale = ttsLocale }
        state.error = nil

        if isDeviceEngine {
            logger.warning("Voice session \(payload.sessionId ?? "?") fell back to on-device speech recognition: sidecar unreachable.")
            if !Self.allowDeviceSttFallback {
                failFatal(code: VoiceErrorCode.sttUnavailable, message: "Speech recognition is unavailable right now.")
                return
            }
            state.notice = "Speech recognition is running on this device."
        }

        // `openCapture()` is THE only place capture opens; `ready` is fired
        // only once it (or its failure) has actually happened, matching the
        // Dart original's `await _openCapture(); _fire(VoiceSignal.ready);`
        // sequencing.
        let myGeneration = generation
        Task { [weak self] in
            await self?.openCapture()
            guard let self, !self.stale(myGeneration) else { return }
            self.fire(.ready)
        }
    }

    private func handleReplySentence(_ payload: VoiceReplySentencePayload) {
        lastSentenceSeq = payload.seq

        // One RTT separates `v.barge` from `v.cancelled`; the server may
        // emit a sentence before it has processed the barge. Drop it rather
        // than speak over the interruption that already happened.
        if let watermark = bargeWatermark, payload.seq >= watermark {
            logger.debug("Dropping reply sentence seq \(payload.seq) behind barge watermark \(watermark).")
            return
        }

        speech.enqueue(seq: payload.seq, text: payload.text, locale: payload.locale)
        fire(.replySentence)
    }

    private func handleLocaleChanged(_ payload: VoiceLocaleChangedPayload) {
        if let sttLocale = payload.sttLocale { state.sttLocale = sttLocale }
        if let ttsLocale = payload.ttsLocale { state.ttsLocale = ttsLocale }
        // Reads the just-updated `state.ttsLocale` rather than the raw
        // payload field, so a locale-changed event that only carried
        // `sttLocale` still names the (unchanged) current TTS locale
        // correctly instead of reporting "Switched to nil.".
        state.notice = localeNotice(reason: payload.reason, ttsLocale: state.ttsLocale)
        fire(.localeChanged)
    }

    private func localeNotice(reason: String?, ttsLocale: String?) -> String? {
        guard let reason, !reason.isEmpty, let ttsLocale else { return nil }
        return "Switched to \(ttsLocale)."
    }

    private func handleCancelled(_ payload: VoiceCancelledPayload) {
        if let fromSeq = payload.fromSeq {
            Task { [speech] in await speech.flushFrom(seq: fromSeq) }
        }
        // The server has caught up — future sentences shouldn't be filtered.
        clearBargeWatermark()
        fire(.cancelled)
    }

    private func handleError(_ payload: VoiceErrorPayload) {
        if payload.fatal == true {
            failFatal(code: payload.code, message: payload.message)
            return
        }

        if payload.code == VoiceErrorCode.sttUnavailable {
            logger.warning("Server lost its STT sidecar mid-session: \(payload.message)")
            if !Self.allowDeviceSttFallback {
                failFatal(code: payload.code, message: payload.message)
                return
            }
            Task { [weak self] in await self?.switchEngine(.device) }
        }

        state.notice = payload.message
        fire(.errorSoft)
    }

    private func failFatal(code: String, message: String) {
        logger.error("Voice conversation failed fatally: \(code) — \(message)")
        state.error = VoiceError(code: code, message: message, fatal: true)
        state.notice = message
        // Closes the mic via `applyPhase`'s idle/error side effect.
        fire(.errorFatal)

        Task { [speech, channel, audioSession] in
            await speech.stopAll()
            channel.close()
            await audioSession.release()
        }
    }

    // MARK: - Transport status

    private func onStatus(_ status: VoiceChannelStatus) {
        let wasReconnecting = state.phase == .reconnecting
        state.connection = status

        switch status {
        case .open:
            if wasReconnecting { fire(.channelRestored) }
            // `v.hello` goes out from the channel's own onConnect handler,
            // not from here — this is only the backstop for it never being
            // answered.
            armReadyWatchdog()
        case .reconnecting:
            fire(.channelLost)
        case .closed:
            // A close during teardown is expected and absorbed by `.idle`.
            fire(.channelLost)
        case .connecting, .idle:
            break
        }
    }

    // MARK: - Audio interruptions

    private func onInterruption(_ interruption: VoiceAudioInterruption) {
        guard state.phase != .idle, state.phase != .error else { return }

        switch interruption {
        case .began:
            // The one documented exception to the mic invariant: not our
            // choice, the platform took the input away.
            micSuspendedByInterruption = true
            Task { [speech] in await speech.stopAll() }
            Task { [weak self] in await self?.closeCapture() }
            fire(.interruptionBegan)
            state.notice = "Audio was interrupted."
            startInterruptionRetry()

        case .ducked:
            // Input is not taken away — just stop the queue so the two
            // don't talk over each other. The turn is unaffected.
            Task { [speech] in await speech.stopAll() }

        case .ended:
            guard micSuspendedByInterruption else { return }
            stopInterruptionRetry()
            micSuspendedByInterruption = false
            Task { [weak self] in await self?.resumeAfterInterruption() }

        case .becomingNoisy:
            // Headphones pulled — don't read into the room.
            Task { [speech] in await speech.stopAll() }

        case .routeChanged:
            break
        }
    }

    private func startInterruptionRetry() {
        interruptionRetryCount = 0
        interruptionRetryTask?.cancel()
        interruptionRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interruptionRetryInterval)
                guard !Task.isCancelled else { return }
                await self?.retryAfterInterruption()
            }
        }
    }

    private func stopInterruptionRetry() {
        interruptionRetryTask?.cancel()
        interruptionRetryTask = nil
        interruptionRetryCount = 0
    }

    private func retryAfterInterruption() async {
        guard micSuspendedByInterruption else { return }
        interruptionRetryCount += 1

        let resumed = await resumeAfterInterruption()
        if resumed {
            stopInterruptionRetry()
        } else if interruptionRetryCount >= Self.maxInterruptionRetries {
            stopInterruptionRetry()
            failFatal(code: "audio_unavailable", message: "Could not resume audio after the interruption.")
        }
    }

    /// `micOpen` after `openCapture()` returns is the honest success signal
    /// — `openCapture()` clears it on any failure path.
    @discardableResult
    private func resumeAfterInterruption() async -> Bool {
        do {
            try await audioSession.acquireForConversation()
        } catch {
            return false
        }

        await openCapture()
        guard micOpen else { return false }

        micSuspendedByInterruption = false
        fire(.interruptionEnded)
        state.notice = nil
        return true
    }

    // MARK: - Locale

    func setLocale(ttsLocale: String, sttLocale: String?) {
        channel.setLocale(ttsLocale: ttsLocale, sttLocale: sttLocale)
        // Optimistic — confirmed or corrected by the `v.locale.changed` echo.
        state.ttsLocale = ttsLocale
        if let sttLocale { state.sttLocale = sttLocale }
    }

    func clearNotice() {
        state.notice = nil
    }

    // MARK: - Watchdogs

    private func armReadyWatchdog() {
        readyWatchdogTask?.cancel()
        let myGeneration = generation
        readyWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: Self.readyTimeout)
            guard !Task.isCancelled else { return }
            self?.handleReadyTimeout(myGeneration)
        }
    }

    private func handleReadyTimeout(_ capturedGeneration: Int) {
        guard !stale(capturedGeneration), state.phase == .preparing else { return }
        failFatal(code: "handshake_timeout", message: "Could not reach the voice service.")
    }

    private func touchTurnWatchdog() {
        guard state.phase == .transcribing || state.phase == .thinking else { return }
        turnTimerTask?.cancel()
        turnTimerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.turnTimeout)
            guard !Task.isCancelled else { return }
            self?.handleTurnTimeout()
        }
    }

    private func handleTurnTimeout() {
        guard state.phase == .transcribing || state.phase == .thinking else { return }
        replyDone = false
        state.notice = "That took too long. Please try again."
        state.replyText = ""
        state.partialTranscript = ""
        // The table maps both stalled phases back to `.listening` on this
        // signal.
        fire(.replyDone)
    }

    // MARK: - Table application

    private func fire(_ signal: VoiceSignal) {
        applyPhase(voiceTransition(from: state.phase, signal: signal))
    }

    /// The microphone invariant is enforced here, and only here: landing on
    /// `.idle`/`.error` closes capture; every other phase leaves it exactly
    /// as it was.
    private func applyPhase(_ next: VoicePhase) {
        guard state.phase != next else { return }
        state.phase = next

        if next == .idle || next == .error {
            micSuspendedByInterruption = false
            stopInterruptionRetry()
            Task { [weak self] in await self?.closeCapture() }
            cancelTimers()
            vad.reset()
            state.level = 0
            return
        }

        if next == .transcribing || next == .thinking {
            touchTurnWatchdog()
        } else {
            turnTimerTask?.cancel()
            turnTimerTask = nil
        }
    }

    // MARK: - Helpers

    private func resetTurn() {
        lastSentenceSeq = 0
        clearBargeWatermark()
        replyDone = false
        queueSpeaking = false
        vadSpeaking = false
        bargeSuppressedUntil = nil
    }

    private func cancelTimers() {
        bargeTimerTask?.cancel()
        bargeTimerTask = nil
        drainTimerTask?.cancel()
        drainTimerTask = nil
        turnTimerTask?.cancel()
        turnTimerTask = nil
        watermarkTimerTask?.cancel()
        watermarkTimerTask = nil
        readyWatchdogTask?.cancel()
        readyWatchdogTask = nil
        stopFrameWatchdog()
        stopInterruptionRetry()
    }
}

/// `Task.sleep(for:)` wants a `Duration`; the frame watchdog needs to
/// compare one against a `Date` difference (a `TimeInterval`). Scoped to
/// this file only — not a general-purpose extension.
fileprivate extension Duration {
    var timeInterval: TimeInterval {
        let comps = components
        return TimeInterval(comps.seconds) + TimeInterval(comps.attoseconds) / 1e18
    }
}
