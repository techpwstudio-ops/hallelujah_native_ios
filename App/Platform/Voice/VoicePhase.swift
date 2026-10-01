import Foundation

/// T59 — ports `VoicePhase` (`lib/features/voice/voice_state.dart`). The
/// eight states a streaming voice conversation moves through; `idle`/`error`
/// are the only two phases where the microphone is guaranteed closed (see
/// `VoiceController.applyPhase(_:)`).
enum VoicePhase: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case transcribing
    case thinking
    case speaking
    case reconnecting
    case error
}

/// Ports `VoiceSignal` — every input the state machine reacts to. Signals
/// are fired by `VoiceController`, never constructed anywhere else, and are
/// looked up in `voiceTransition(from:signal:)` to find the next phase.
enum VoiceSignal: Equatable, Sendable {
    case started
    case ready
    case speechStart
    case sttPartial
    case sttFinal
    case replyDelta
    case replySentence
    case replyDone
    case cancelled
    case localeChanged
    case barge
    case vadOnset
    case vadOffset
    case errorSoft
    case errorFatal
    case channelLost
    case channelRestored
    case interruptionBegan
    case interruptionEnded
    case stopped
}

/// Ports `VoiceError` (`voice_state.dart`).
struct VoiceError: Equatable, Sendable {
    let code: String
    let message: String
    var fatal: Bool = false
}

/// Ports `ChannelStatus` (`lib/features/voice/net/realtime_channel.dart`) —
/// kept as its own type (not reusing `RealtimeConnectionManager.Status`,
/// T67) because the voice channel has a `reconnecting` state that manager
/// doesn't model at all: T67's socket.io-client-swift reconnection is
/// handled entirely internally, while `/voice` drives its own ladder
/// (`VoiceReconnectPolicy`) and needs to expose the in-between state.
enum VoiceChannelStatus: Equatable, Sendable {
    case idle
    case connecting
    case open
    case reconnecting
    case closed
}

/// Ports `VoiceState` (`voice_state.dart`) — the single `@Observable` struct
/// `VoiceController` publishes every field from.
struct VoiceState: Equatable, Sendable {
    var phase: VoicePhase = .idle
    var connection: VoiceChannelStatus = .idle
    var conversationID: String?
    var partialTranscript: String = ""
    var transcript: String = ""
    var replyText: String = ""
    var level: Double = 0
    var sttLocale: String?
    var ttsLocale: String?
    var notice: String?
    var error: VoiceError?

    var isActive: Bool { phase != .idle && phase != .error }

    /// Ports `caption` — what the overlay renders as its one line of text.
    var caption: String {
        if phase == .speaking || phase == .thinking, !replyText.isEmpty {
            return replyText
        }
        return partialTranscript.isEmpty ? transcript : partialTranscript
    }
}

/// Ports `kVoiceTransitions` — the exhaustive 8-phase x 20-signal lookup
/// table (`voice_controller.dart:101-298`) as nested exhaustive switches
/// rather than a dictionary literal, so the compiler — not a debug-only
/// assert like Dart's — catches a missing pair at build time.
///
/// `idle` and `error` are self-absorbing rows in the Dart source ("every
/// signal maps back to the same phase, except these one or two"); every
/// other row lists all 20 signals individually. Transcribed verbatim,
/// signal by signal, from the real `kVoiceTransitions` map.
func voiceTransition(from phase: VoicePhase, signal: VoiceSignal) -> VoicePhase {
    switch phase {
    case .idle:
        switch signal {
        case .started: return .preparing
        default: return .idle
        }

    case .preparing:
        switch signal {
        case .started: return .preparing
        case .ready: return .listening
        case .speechStart: return .listening
        case .sttPartial: return .preparing
        case .sttFinal: return .thinking
        case .replyDelta: return .preparing
        case .replySentence: return .speaking
        case .replyDone: return .preparing
        case .cancelled: return .preparing
        case .localeChanged: return .preparing
        case .barge: return .preparing
        case .vadOnset: return .preparing
        case .vadOffset: return .preparing
        case .errorSoft: return .preparing
        case .errorFatal: return .error
        case .channelLost: return .reconnecting
        case .channelRestored: return .preparing
        case .interruptionBegan: return .reconnecting
        case .interruptionEnded: return .preparing
        case .stopped: return .idle
        }

    case .listening:
        switch signal {
        case .started: return .listening
        case .ready: return .listening
        case .speechStart: return .listening
        case .sttPartial: return .listening
        case .sttFinal: return .thinking
        case .replyDelta: return .thinking
        case .replySentence: return .speaking
        case .replyDone: return .listening
        case .cancelled: return .listening
        case .localeChanged: return .listening
        case .barge: return .listening
        case .vadOnset: return .listening
        case .vadOffset: return .transcribing
        case .errorSoft: return .listening
        case .errorFatal: return .error
        case .channelLost: return .reconnecting
        case .channelRestored: return .listening
        case .interruptionBegan: return .reconnecting
        case .interruptionEnded: return .listening
        case .stopped: return .idle
        }

    case .transcribing:
        switch signal {
        case .started: return .transcribing
        case .ready: return .listening
        case .speechStart: return .listening
        case .sttPartial: return .transcribing
        case .sttFinal: return .thinking
        case .replyDelta: return .thinking
        case .replySentence: return .speaking
        case .replyDone: return .listening
        case .cancelled: return .transcribing
        case .localeChanged: return .transcribing
        case .barge: return .transcribing
        case .vadOnset: return .listening
        case .vadOffset: return .transcribing
        case .errorSoft: return .transcribing
        case .errorFatal: return .error
        case .channelLost: return .reconnecting
        case .channelRestored: return .transcribing
        case .interruptionBegan: return .reconnecting
        case .interruptionEnded: return .transcribing
        case .stopped: return .idle
        }

    case .thinking:
        switch signal {
        case .started: return .thinking
        case .ready: return .listening
        case .speechStart: return .listening
        case .sttPartial: return .listening
        case .sttFinal: return .thinking
        case .replyDelta: return .thinking
        case .replySentence: return .speaking
        case .replyDone: return .listening
        case .cancelled: return .thinking
        case .localeChanged: return .thinking
        case .barge: return .thinking
        case .vadOnset: return .listening
        case .vadOffset: return .thinking
        case .errorSoft: return .thinking
        case .errorFatal: return .error
        case .channelLost: return .reconnecting
        case .channelRestored: return .thinking
        case .interruptionBegan: return .reconnecting
        case .interruptionEnded: return .thinking
        case .stopped: return .idle
        }

    case .speaking:
        switch signal {
        case .started: return .speaking
        case .ready: return .listening
        case .speechStart: return .listening
        case .sttPartial: return .speaking
        case .sttFinal: return .thinking
        case .replyDelta: return .speaking
        case .replySentence: return .speaking
        case .replyDone: return .listening
        case .cancelled: return .speaking
        case .localeChanged: return .speaking
        case .barge: return .listening
        case .vadOnset: return .speaking
        case .vadOffset: return .speaking
        case .errorSoft: return .speaking
        case .errorFatal: return .error
        case .channelLost: return .reconnecting
        case .channelRestored: return .speaking
        case .interruptionBegan: return .reconnecting
        case .interruptionEnded: return .speaking
        case .stopped: return .idle
        }

    case .reconnecting:
        switch signal {
        case .started: return .reconnecting
        case .ready: return .listening
        case .speechStart: return .listening
        case .sttPartial: return .listening
        case .sttFinal: return .thinking
        case .replyDelta: return .reconnecting
        case .replySentence: return .speaking
        case .replyDone: return .reconnecting
        case .cancelled: return .reconnecting
        case .localeChanged: return .reconnecting
        case .barge: return .reconnecting
        case .vadOnset: return .reconnecting
        case .vadOffset: return .reconnecting
        case .errorSoft: return .reconnecting
        case .errorFatal: return .error
        case .channelLost: return .reconnecting
        case .channelRestored: return .listening
        case .interruptionBegan: return .reconnecting
        case .interruptionEnded: return .listening
        case .stopped: return .idle
        }

    case .error:
        switch signal {
        case .started: return .preparing
        case .stopped: return .idle
        default: return .error
        }
    }
}
