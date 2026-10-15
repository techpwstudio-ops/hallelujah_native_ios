import AVFoundation
import Foundation

/// T59 — ports `AudioInterruption` (`lib/features/voice/audio/audio_session_owner.dart`).
/// Something the platform did to our audio that was not asked for.
enum VoiceAudioInterruption: Sendable {
    /// A phone call, Siri, an alarm — playback and capture are gone for
    /// now.
    case began

    /// Something else wants to be heard over us for a moment. The input is
    /// NOT taken away.
    ///
    /// Dart's `audio_session` plugin distinguishes this from `began` using
    /// `AudioInterruptionType.duck`. Plain `AVAudioSession` has no native
    /// equivalent: iOS attenuates a ducked app's output at the mixer level
    /// without posting any interruption notification for it, so this case
    /// is kept for API parity but is never actually emitted here — every
    /// genuine iOS interruption arrives as `.began`. Flagged as a known,
    /// deliberate gap versus the Dart original rather than a guessed
    /// implementation.
    case ducked

    /// The interruption is over; it is safe to resume.
    case ended

    /// Headphones were unplugged or a Bluetooth device walked away — audio
    /// is about to blast out of the speaker. Ports the `AVAudioSession`
    /// idiom of reading `routeChangeNotification`'s reason as
    /// `.oldDeviceUnavailable`, which is what Android's dedicated
    /// "becoming noisy" broadcast maps to.
    case becomingNoisy

    /// The input or output route changed without becoming noisy — a
    /// headset connected, a car stereo took over.
    case routeChanged
}

/// The one and only claimant of the platform audio session during a voice
/// conversation. Ports `AudioSessionOwner`.
///
/// Two components want to touch the session during a voice turn — this
/// conversation's mic capture and its TTS — and on iOS the last one to call
/// `setCategory` wins. So neither of them do: `AVEngineVoiceMicCapture`
/// and `VoiceSpeechQueue` both leave `AVAudioSession` alone, and this class
/// configures the session once, for the whole conversation.
///
/// The configuration below is the load-bearing part. `.playAndRecord` +
/// `.voiceChat` is what makes CoreAudio install the Voice-Processing I/O
/// unit, which gives hardware acoustic echo cancellation — the difference
/// between an assistant that can be interrupted mid-sentence and one that
/// transcribes its own voice back into the conversation.
@MainActor
final class VoiceAudioSessionOwner {
    static let shared = VoiceAudioSessionOwner()
    private init() {}

    var onInterruption: ((VoiceAudioInterruption) -> Void)?

    /// Simple guard rather than a refcount: a conversation is a single,
    /// user-visible thing. Two overlapping voice conversations is a bug,
    /// not a case to support, and a refcount would quietly paper over it.
    private(set) var isHeld = false
    private var acquiring = false

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    /// Configures and activates the session for full-duplex voice.
    ///
    /// Idempotent — calling it twice is a no-op, and concurrent calls
    /// collapse into the first.
    func acquireForConversation() async throws {
        if isHeld || acquiring { return }
        acquiring = true
        defer { acquiring = false }

        let session = AVAudioSession.sharedInstance()
        do {
            // `.defaultToSpeaker` matters because `.playAndRecord`
            // otherwise routes playback to the earpiece — the assistant
            // would be inaudible unless the phone were held to the ear.
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            listen(on: session)

            do {
                try session.setActive(true)
            } catch {
                // Another app holds an exclusive session (an in-progress
                // phone call is the usual one). Capture would fail
                // anyway; surface it as an interruption so the caller can
                // back out gracefully.
                onInterruption?(.began)
                return
            }

            isHeld = true
        } catch {
            throw error
        }
    }

    /// Deactivates and hands the session back.
    ///
    /// Idempotent. Failures are swallowed: the only thing a throw here
    /// could achieve is preventing the rest of the teardown from running.
    func release() async {
        guard isHeld else {
            // Still detach: acquire() may have wired listeners before
            // failing to activate, and leaving them attached leaks a
            // subscription per attempt.
            detach()
            return
        }
        isHeld = false

        detach()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Nothing to recover from here — the goal was "not holding the
            // session", and failing to deactivate doesn't change that.
        }
    }

    private func listen(on session: AVAudioSession) {
        // Re-attaching without detaching first is how a second
        // conversation ends up delivering every interruption twice.
        detach()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeValue: typeValue) }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.handleRouteChange(reasonValue: reasonValue) }
        }
    }

    private func detach() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    private func handleInterruption(typeValue: UInt?) {
        guard
            let typeValue,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            emit(.began)
        case .ended:
            emit(.ended)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard
            let reasonValue,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .oldDeviceUnavailable:
            emit(.becomingNoisy)
        case .newDeviceAvailable, .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory, .routeConfigurationChange:
            emit(.routeChanged)
        default:
            break
        }
    }

    private func emit(_ event: VoiceAudioInterruption) {
        onInterruption?(event)
    }

    /// True where `.voiceChat` actually engages a hardware echo canceller
    /// — always, on iOS.
    static let hasHardwareEchoCancellation = true
}
