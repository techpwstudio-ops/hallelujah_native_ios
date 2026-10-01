import Foundation

/// Full-screen-cover presentations, mirroring the only three targets
/// `NavigationService.pushModal` actually pushes (`lib/services/
/// navigation_service.dart`; every call site was grepped to confirm this):
/// the full player (from the mini-player dock and the ad-break banner) and
/// the two hands-free-voice pages, which are mutually exclusive behind
/// Dart's `VoiceFeature.useStreamingVoice` flag.
///
/// `.player` carries no payload here — Dart's `AudioPlayerScreen(isCustom:)`
/// flag selects which queue it's showing, which belongs to whatever owns
/// playback state (not built yet) rather than the navigation layer.
enum FullScreenDestination: Hashable, Sendable, Identifiable {
    case player
    case aiVoiceOverlay
    case aiAudioConversation(conversationID: String?)

    var id: Self { self }
}
