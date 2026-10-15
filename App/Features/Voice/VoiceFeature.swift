import Foundation

/// `VoiceFeature` (`lib/features/voice/voice_feature_flag.dart`).
enum VoiceFeature {
    /// Whether the microphone button appears in the AI input bar at all.
    /// Flutter ships `showVoiceEntryPoint = false` (the whisper sidecar is not
    /// deployed), which takes the only user-facing way into the voice loop off
    /// the shelf; the voice screens stay compiled and wired. Flip to `true` to
    /// bring the mic button back.
    static let showVoiceEntryPoint = false
}
