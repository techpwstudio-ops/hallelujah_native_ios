import Foundation

/// T59 — ports `LocalVad` (`lib/features/voice/vad/local_vad.dart`).
///
/// On-device voice activity detection over the outgoing PCM frames. This
/// exists for two jobs and no others:
///
///  1. **Barge-in.** While the assistant is speaking there is no server-side
///     recognition running to notice the user cutting in, and waiting for a
///     round trip to find out would make interrupting feel broken. RMS on
///     frames already being produced costs nothing and answers within one
///     100ms frame.
///  2. **The orb.** `level` is a smoothed 0...1 the UI can breathe with.
///
/// It emphatically does NOT decide end-of-turn. That belongs to the
/// server's VAD, which has the full audio and a model behind it; an RMS
/// threshold would cut people off at every pause for thought.
@MainActor
final class VoiceLocalVAD {
    /// Normalised RMS (0...1 of full scale) above which a frame counts as
    /// speech. ~0.02 is roughly -34 dBFS: comfortably above the noise floor
    /// of a phone held at arm's length, comfortably below conversational
    /// speech. Barge-in wants to err towards missing a whisper rather than
    /// towards the assistant interrupting itself over a passing bus.
    private static let defaultSpeechRMS: Double = 0.02

    /// Exponential smoothing weight for `level`. 0.3 on the new sample
    /// gives the orb roughly a 300ms tail at 100ms frames — responsive
    /// without jitter. Same coefficient as the Dart original.
    private static let levelSmoothing: Double = 0.3

    private let speechRMS: Double
    private let hangover: Duration

    /// Fires on every speaking/not-speaking transition. Does not replay: a
    /// listener attached after a transition gets only the next one, not the
    /// last one — matching the Dart broadcast stream's semantics. Read
    /// `isSpeaking` for the current value.
    var onSpeakingChanged: ((Bool) -> Void)?

    /// True from the first speech frame until `hangover` elapses with none.
    private(set) var isSpeaking = false

    /// Smoothed 0...1 loudness for the UI.
    ///
    /// Normalised against the floor and ceiling actually observed rather
    /// than against full scale: absolute RMS in a quiet room barely leaves
    /// the bottom of the range, and an orb that never moves is worse than
    /// no orb. The trade-off is that the very first moments of a session
    /// read low until the range has been seen — which is correct, nothing
    /// has been heard yet.
    private(set) var level: Double = 0

    private var hangoverTask: Task<Void, Never>?
    private var closed = false

    private var floor: Double = 1
    private var ceiling: Double = 0
    private var smoothed: Double = 0

    init(speechRMS: Double = VoiceLocalVAD.defaultSpeechRMS, hangover: Duration = .milliseconds(400)) {
        self.speechRMS = speechRMS
        self.hangover = hangover
    }

    /// Feeds one PCM16LE frame. Frame size is not checked beyond needing at
    /// least one whole sample — `VoiceMicCapture` guarantees exactly
    /// `VoiceAudioFormat.frameBytes`.
    func feed(_ frame: Data) {
        guard !closed, frame.count >= 2 else { return }

        let rms = rmsOf(frame)
        updateLevel(rms)

        if rms >= speechRMS {
            onSpeechFrame()
        }
    }

    /// Root-mean-square of the frame, as a fraction of full scale.
    ///
    /// Reads via `loadUnaligned` rather than binding the bytes to
    /// `Int16` directly: a `Data` frame handed down from the audio
    /// converter is not guaranteed to be two-byte aligned, and an aligned
    /// load traps on an odd offset. `Int16` loaded this way is
    /// native-endian, which — unlike Dart, which has to say so explicitly —
    /// is little-endian on every platform this app runs on, matching the
    /// PCM16LE wire format without any extra step.
    private func rmsOf(_ frame: Data) -> Double {
        let sampleCount = frame.count / 2
        guard sampleCount > 0 else { return 0 }

        var sumSquares: Double = 0
        frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0 ..< sampleCount {
                let sample = raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)
                let normalized = Double(sample) / 32768.0
                sumSquares += normalized * normalized
            }
        }
        return (sumSquares / Double(sampleCount)).squareRoot()
    }

    private func updateLevel(_ rms: Double) {
        if rms < floor { floor = rms }
        if rms > ceiling { ceiling = rms }

        let span = abs(ceiling - floor)
        let raw = span < 0.001 ? 0.0 : (rms - floor) / span
        smoothed = smoothed * (1 - Self.levelSmoothing) + min(max(raw, 0), 1) * Self.levelSmoothing
        level = smoothed
    }

    private func onSpeechFrame() {
        if !isSpeaking {
            isSpeaking = true
            onSpeakingChanged?(true)
        }

        // Every speech frame pushes the offset back out. The hangover is
        // what stops a natural pause mid-sentence from reading as two
        // separate barge-ins. Cancel-and-reschedule, exactly like the Dart
        // `Timer`.
        hangoverTask?.cancel()
        hangoverTask = Task { [weak self, hangover] in
            try? await Task.sleep(for: hangover)
            guard !Task.isCancelled else { return }
            self?.handleHangoverElapsed()
        }
    }

    private func handleHangoverElapsed() {
        guard isSpeaking else { return }
        isSpeaking = false
        onSpeakingChanged?(false)
    }

    /// Clears state between turns.
    ///
    /// The observed range is reset too: the assistant's own playback and
    /// the user's voice have different levels, and a ceiling learned from
    /// one flattens the orb for the other.
    func reset() {
        hangoverTask?.cancel()
        hangoverTask = nil

        if isSpeaking {
            isSpeaking = false
            onSpeakingChanged?(false)
        }

        floor = 1
        ceiling = 0
        smoothed = 0
        level = 0
    }

    func dispose() {
        guard !closed else { return }
        closed = true
        hangoverTask?.cancel()
        hangoverTask = nil
    }
}
