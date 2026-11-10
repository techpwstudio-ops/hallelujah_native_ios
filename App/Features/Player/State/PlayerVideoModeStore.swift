import Observation

/// Whether the full player shows an episode's silent video over the cover, or the cover.
///
/// The listener's choice, kept for the life of the app and not saved: every launch starts on the
/// cover. One instance is shared by the full player's artwork and the switch that flips it.
@MainActor
@Observable
final class PlayerVideoModeStore {
    private(set) var showsVideo = false

    func showVideo() { showsVideo = true }

    func showCover() { showsVideo = false }

    func toggle() { showsVideo.toggle() }
}
