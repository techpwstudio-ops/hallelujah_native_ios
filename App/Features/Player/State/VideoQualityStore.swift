import Observation

/// The listener's video quality, shared by Settings, the full player and the full-screen video.
///
/// Holds the stored preference and a snapshot of the conditions "Auto" decides from. The snapshot is
/// taken when a track opens (`refreshConditions()`), not continuously: the picture is chosen once per
/// episode, so walking out of Wi-Fi range mid-episode does not reload it. A change of preference is
/// the one thing that does, and because every view reads `choice(for:)` from here, they all reload
/// together, at the audio's current position, while the audio keeps playing.
@MainActor
@Observable
final class VideoQualityStore {
    private let selector: VideoQualitySelector

    /// What the listener picked. `auto` until they pick.
    private(set) var preference: VideoQuality
    /// `nil` until the first `refreshConditions()` lands.
    private(set) var conditions: VideoQualityConditions?

    init(selector: VideoQualitySelector) {
        self.selector = selector
        preference = selector.userSelectedQuality
    }

    func setPreference(_ quality: VideoQuality) {
        guard quality != preference else { return }
        selector.setUserSelectedQuality(quality)
        preference = quality
    }

    func refreshConditions() async {
        let latest = await selector.currentConditions()
        if latest != conditions { conditions = latest }
    }

    /// Whether `choice(for:)` can answer. Auto needs the conditions; an explicit pick does not.
    var isReady: Bool { preference != .auto || conditions != nil }

    /// What to play for `song`; `nil` while Auto is still waiting for the conditions.
    func choice(for song: Song) -> VideoQualityChoice? {
        guard isReady else { return nil }
        return selector.choice(for: song, conditions: conditions ?? VideoQualityConditions())
    }

    /// The concrete qualities this episode offers on this device, lowest to highest. Fewer than two
    /// means there is nothing to choose between.
    func options(for song: Song) -> [VideoQuality] {
        selector.renditions(for: song).qualities
    }
}
