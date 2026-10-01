import AVFoundation
import Foundation

/// One ready-to-speak unit, as it arrived on `v.reply.sentence`. `seq` is
/// monotonic within a reply — this is what makes barge-in exact: everything
/// at or above the seq the user interrupted on is dropped, everything below
/// it has already been heard.
private struct VoiceUtterance {
    let seq: Int
    let text: String
    let locale: String?
}

/// T59 — ports `SpeechQueue` (`lib/features/voice/audio/speech_queue.dart`)
/// onto `AVSpeechSynthesizer`.
///
/// Speaks reply sentences, one at a time, in order. Only ever hands the
/// synthesizer a single utterance at a time — the next one starts from the
/// completion callback — so this class's own queue, not
/// `AVSpeechSynthesizer`'s built-in one, is the thing driving order. That
/// keeps the exact-seq flush-on-barge-in semantics below possible, which a
/// bare "let the engine queue everything" approach would not allow.
///
/// The whole difficulty of this class is the callback race, worth stating
/// plainly: when `stopSpeaking(at:)` cuts an utterance short, whether
/// `didCancel` or `didFinish` fires — or, if nothing was speaking, neither —
/// can be ambiguous, and the callback can land after the next utterance has
/// already started. A boolean "we are cancelling" flag gets cleared too
/// early and lets a stale callback advance the queue past a sentence.
/// `pendingCancelCount` is the fix, ported from the same reasoning as
/// Dart's `_pendingCancelCount` (itself shared with
/// `river_pods/tts_player_provider.dart`). Each intentional stop that the
/// engine can still answer adds one; each callback that finds the counter
/// non-zero consumes one and returns without touching the queue.
@MainActor
final class VoiceSpeechQueue: NSObject {
    /// Natural pace — `AVSpeechUtteranceDefaultSpeechRate` is the engine's
    /// own default, matching Dart's "0.5 is the engine's own default"
    /// scale intent.
    private static let naturalSpeechRate = AVSpeechUtteranceDefaultSpeechRate

    /// How long a stopped utterance has to report back before this queue
    /// assumes the engine has swallowed the callback and unwedges itself.
    private static let cancelCallbackGrace: Duration = .seconds(3)

    /// Ceiling on unspoken sentences. A reply is a handful of sentences;
    /// anything approaching this is a bug upstream or a queue that has
    /// stopped draining, and an unbounded array fed from a socket is a
    /// memory leak with extra steps.
    private static let maxQueuedUtterances = 64

    /// Stopping releases synthesis resources; speaking again immediately
    /// can be swallowed while that teardown is still in flight. A short
    /// gap makes the next utterance reliable.
    private static let settleAfterStop: Duration = .milliseconds(300)

    var onSpeakingChanged: ((Bool) -> Void)?

    /// True while a sentence is being spoken. Drives the UI's speaking
    /// state and tells the controller when it is safe to reopen the mic.
    private(set) var isSpeaking = false

    /// Seq of the sentence currently being spoken, or nil when idle.
    var currentSeq: Int? { current?.seq }

    private let synthesizer = AVSpeechSynthesizer()

    private var queue: [VoiceUtterance] = []
    private var current: VoiceUtterance?
    private var busy = false
    private var disposed = false

    /// See the class doc. Never reset to zero except when the cancel
    /// watchdog fires.
    private var pendingCancelCount = 0

    /// True only between handing an utterance to the engine and the engine
    /// reporting back on it. This is the difference between a cancel that
    /// will produce a callback and one that will not, and getting it wrong
    /// wedges the queue permanently.
    private var handedToEngine = false

    /// Last resort for an engine that acknowledges neither the cancel nor
    /// the completion of a stopped utterance.
    private var cancelWatchdog: Task<Void, Never>?

    /// Bumped by anything that supersedes work already in flight — a
    /// flush, a stop, a dispose. `speak(_:)` re-checks it and bails rather
    /// than speaking a sentence the user has already interrupted.
    private var generation = 0

    /// Best voice found per locale tag. Enumerating voices is not free, and
    /// the answer only changes when the user installs one.
    private var voiceByLocale: [String: AVSpeechSynthesisVoice?] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Setup

    /// Pays the cold-start cost up front. The first `speak()` of a process
    /// is a visible beat of silence while the synthesis engine spins up;
    /// spending it on a single space during the connect handshake means
    /// the first real sentence starts instantly.
    func prewarm() {
        guard !disposed else { return }
        let warm = AVSpeechUtterance(string: " ")
        warm.voice = resolveVoice(forServerLocale: SpeechLocales.defaultLocale)
        warm.rate = Self.naturalSpeechRate
        synthesizer.speak(warm)
    }

    // MARK: Queue

    /// Adds a sentence to the back of the queue and starts it if idle.
    /// Synchronous by contract: called straight from the socket event
    /// handler, which must not be made to wait on the speech engine.
    func enqueue(seq: Int, text: String, locale: String?) {
        guard !disposed else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if queue.count >= Self.maxQueuedUtterances {
            // Drop the NEWEST, not the oldest: truncating the tail of a
            // reply is merely incomplete, whereas dropping from the front
            // makes what the user hears jump mid-thought.
            return
        }

        queue.append(VoiceUtterance(seq: seq, text: text, locale: locale))
        pump()
    }

    private func pump() {
        guard !disposed, !busy, !queue.isEmpty else { return }

        let next = queue.removeFirst()
        current = next
        busy = true
        setSpeaking(true)
        Task { await speak(next) }
    }

    private func speak(_ utterance: VoiceUtterance) async {
        let generationAtStart = generation
        guard !isSuperseded(generationAtStart, utterance) else { return }

        let voice = resolveVoice(forServerLocale: utterance.locale)
        guard !isSuperseded(generationAtStart, utterance) else { return }

        let speechUtterance = AVSpeechUtterance(string: utterance.text)
        speechUtterance.voice = voice
        speechUtterance.rate = Self.naturalSpeechRate
        speechUtterance.pitchMultiplier = 1.0
        speechUtterance.volume = 1.0

        // Set immediately before the call, never earlier: everything above
        // this line is a window in which a stop must NOT count a pending
        // cancel.
        handedToEngine = true
        synthesizer.speak(speechUtterance)
    }

    private func isSuperseded(_ generationAtStart: Int, _ utterance: VoiceUtterance) -> Bool {
        disposed || generation != generationAtStart || current?.seq != utterance.seq
    }

    /// The one place a sentence's end is handled, from either delegate
    /// callback.
    private func handleUtteranceEnded() {
        handedToEngine = false

        if pendingCancelCount > 0 {
            // An utterance cut short deliberately. Treating it as
            // "finished speaking" would advance the queue past a sentence
            // the flush was supposed to keep, or reopen the mic in the
            // middle of a barge-in.
            pendingCancelCount -= 1
            if pendingCancelCount == 0 {
                cancelWatchdog?.cancel()
                cancelWatchdog = nil
            }
            return
        }
        advance()
    }

    /// Recovers from an engine that never reported back on a stop.
    private func armCancelWatchdog() {
        cancelWatchdog?.cancel()
        cancelWatchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.cancelCallbackGrace)
            guard !Task.isCancelled else { return }
            self?.handleCancelWatchdogFired()
        }
    }

    private func handleCancelWatchdogFired() {
        cancelWatchdog = nil
        guard !disposed, pendingCancelCount != 0 else { return }

        pendingCancelCount = 0
        guard !busy else { return }
        if queue.isEmpty {
            setSpeaking(false)
        } else {
            pump()
        }
    }

    private func advance() {
        current = nil
        busy = false
        handedToEngine = false

        if queue.isEmpty {
            setSpeaking(false)
            return
        }
        pump()
    }

    /// Drops everything at or above `seq`, including the sentence being
    /// spoken. This is barge-in. The server sends the same boundary back
    /// on `v.cancelled`, so calling this from both the local VAD and the
    /// server event is safe — the second call finds nothing left to drop.
    func flushFrom(seq: Int) async {
        guard !disposed else { return }

        queue.removeAll { $0.seq >= seq }

        if let current, current.seq >= seq {
            // Only now, and only here: bumping the generation
            // unconditionally would abort an in-flight `speak(_:)` for a
            // sentence BELOW the flush point that has not reached the
            // engine yet, leaving `busy` stuck true and the queue wedged
            // for the rest of the conversation.
            generation += 1
            await stopCurrent()
        }

        if !busy {
            if queue.isEmpty {
                setSpeaking(false)
            } else {
                pump()
            }
        }
    }

    /// Silences everything, queued and in flight. Used when the
    /// conversation ends, or when the audio session is taken away.
    func stopAll() async {
        guard !disposed else { return }

        generation += 1
        queue.removeAll()
        // Announced BEFORE the await below — `stopCurrent()` owes ~300ms
        // of settle time, and a sentence that arrives inside that window
        // starts speaking, which a trailing `setSpeaking(false)` would
        // then contradict.
        setSpeaking(false)
        await stopCurrent()
    }

    private func stopCurrent() async {
        // Only count a cancel the ENGINE can answer. `busy`/`current` are
        // set by `pump()` before the text reaches the engine, so they say
        // "a sentence is being started", not "a sentence is being
        // spoken" — counting on them is what would leave the counter
        // permanently ahead and swallow the next genuine completion.
        // `handedToEngine` is the narrower, correct question.
        let expectCallback = handedToEngine

        current = nil
        busy = false
        handedToEngine = false

        if expectCallback { pendingCancelCount += 1 }

        // `stopSpeaking` returns false when nothing was actually speaking
        // or paused — no callback is coming for that, so the count is
        // undone immediately rather than waiting on the watchdog.
        let stopped = synthesizer.stopSpeaking(at: .immediate)
        if expectCallback {
            if stopped {
                armCancelWatchdog()
            } else {
                pendingCancelCount -= 1
            }
        }

        try? await Task.sleep(for: Self.settleAfterStop)
    }

    private func setSpeaking(_ value: Bool) {
        guard isSpeaking != value else { return }
        isSpeaking = value
        onSpeakingChanged?(value)
    }

    func dispose() {
        guard !disposed else { return }
        generation += 1
        queue.removeAll()
        cancelWatchdog?.cancel()
        cancelWatchdog = nil
        _ = synthesizer.stopSpeaking(at: .immediate)
        disposed = true
    }

    // MARK: Locale and voice selection
    //
    // Reuses `SpeechLocales` (T57)'s public locale constants and its
    // `iso(ofLocale:)` ISO-639-1 extraction. `SpeechLocales.bestVoice(
    // forLanguageName:)` itself is keyed by a Bible-content display name
    // ("Telugu"), not the BCP-47 tag `v.reply.sentence.locale` carries
    // ("te-IN"), and its quality-ranking table is private — so the small
    // filter/rank loop below is reimplemented against a locale-tag key
    // rather than reused directly, mirroring `SpeechLocales.bestVoice`'s
    // algorithm exactly (same quality ranks: premium=3, enhanced=2,
    // default=1). Keep the two in step if either changes.

    private func resolveVoice(forServerLocale locale: String?) -> AVSpeechSynthesisVoice? {
        var candidates: [String] = []
        if let locale, !locale.isEmpty { candidates.append(locale) }
        candidates.append(SpeechLocales.defaultLocale)
        candidates.append(SpeechLocales.fallbackLocale)

        for candidate in candidates {
            if let voice = cachedVoice(forLocaleTag: candidate) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: SpeechLocales.defaultLocale)
    }

    private func cachedVoice(forLocaleTag tag: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceByLocale[tag] { return cached }
        let found = bestVoice(forLocaleTag: tag)
        voiceByLocale[tag] = found
        return found
    }

    private func bestVoice(forLocaleTag tag: String) -> AVSpeechSynthesisVoice? {
        let targetISO = SpeechLocales.iso(ofLocale: tag)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { SpeechLocales.iso(ofLocale: $0.language) == targetISO }
            .max { qualityRank($0.quality) < qualityRank($1.quality) }
    }

    private func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 0
        }
    }
}

extension VoiceSpeechQueue: AVSpeechSynthesizerDelegate {
    /// `AVSpeechSynthesizerDelegate`'s methods are `nonisolated` in the
    /// SDK; conforming this `@MainActor` type requires hopping via `Task`
    /// to the actor-isolated body, the same pattern `ReadAloudController`
    /// (T57) uses for the same reason.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.handleUtteranceEnded() }
    }

    /// The cancel callback and the finish callback are handled identically
    /// — engines disagree about which of the two an interrupted utterance
    /// produces, so both consult `pendingCancelCount`.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.handleUtteranceEnded() }
    }
}
