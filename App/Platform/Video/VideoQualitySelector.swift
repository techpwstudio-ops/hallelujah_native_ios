import Foundation

/// What is around the device when "Auto" decides: the facts that make a smaller picture the
/// kinder choice.
struct VideoQualityConditions: Sendable, Equatable {
    /// `nil` until the first network reading arrives. Treated as "no cap yet", the way
    /// `AudioQualitySelector` treats it, rather than as the worst case.
    var connection: ConnectionType?
    var isLowBattery = false
    var isLowPowerMode = false

    /// Auto stays at the smallest picture: on mobile data (or any connection that is not known to be
    /// Wi-Fi or ethernet), offline, on a low battery, or in Low Power Mode.
    var isConstrained: Bool {
        if isLowBattery || isLowPowerMode { return true }
        guard let connection else { return false }
        switch connection {
        case .wifi, .ethernet: return false
        case .cellular, .other, .none: return true
        }
    }
}

/// The encoded renditions a song has and the original, narrowed to what this device can play.
struct VideoRenditions: Sendable, Equatable {
    /// Rung to the file name the backend sent for it (`480p` -> `480p.mp4`).
    let variantFileNames: [VideoQuality: String]
    /// The original `videoFile` can be played here.
    let offersOriginal: Bool

    /// Every quality worth offering for this song, lowest to highest.
    var qualities: [VideoQuality] {
        VideoQuality.rungs.filter { variantFileNames[$0] != nil } + (offersOriginal ? [VideoQuality.original] : [])
    }

    var hasVariants: Bool { !variantFileNames.isEmpty }
}

/// The resolved target for one song.
struct VideoQualityChoice: Sendable, Equatable {
    /// The concrete quality being played (never `auto`).
    let quality: VideoQuality
    /// The file beside `videoFile` to play (`720p.mp4`); `nil` plays `videoFile` itself.
    let variantFileName: String?

    static let original = VideoQualityChoice(quality: .original, variantFileName: nil)
}

/// Decides which version of an episode's silent video to play. The counterpart of
/// `AudioQualitySelector` for the picture: the stored preference and the live signals sit in the
/// instance, and the decision itself is `static` and pure so every rule is testable on its own.
///
/// Unlike the audio selector, an explicit choice is not capped by the network or the battery: the
/// listener asked for that picture. Only Auto reacts to conditions.
struct VideoQualitySelector: Sendable {
    private static let userQualityKey = "video.selectedQuality"

    private let keyValueStore: any KeyValueStoring
    private let batteryMonitor: any BatteryLevelMonitoring
    private let connectivityType: any ConnectivityTypeProviding
    private let lowPowerMode: any LowPowerModeProviding
    private let capability: VideoDecodeCapability

    init(
        keyValueStore: any KeyValueStoring,
        batteryMonitor: any BatteryLevelMonitoring,
        connectivityType: any ConnectivityTypeProviding,
        lowPowerMode: any LowPowerModeProviding,
        capability: VideoDecodeCapability
    ) {
        self.keyValueStore = keyValueStore
        self.batteryMonitor = batteryMonitor
        self.connectivityType = connectivityType
        self.lowPowerMode = lowPowerMode
        self.capability = capability
    }

    // MARK: Stored preference

    /// The listener's choice, `auto` until they make one (or if the stored value is unreadable).
    var userSelectedQuality: VideoQuality {
        keyValueStore.string(forKey: Self.userQualityKey).flatMap(VideoQuality.init(rawValue:)) ?? .auto
    }

    func setUserSelectedQuality(_ quality: VideoQuality) {
        keyValueStore.setString(quality.rawValue, forKey: Self.userQualityKey)
    }

    // MARK: Live signals

    func currentConditions() async -> VideoQualityConditions {
        async let connection = connectivityType.currentConnectionType
        async let lowBattery = batteryMonitor.isLowBattery
        async let lowPower = lowPowerMode.isLowPowerModeEnabled
        return await VideoQualityConditions(
            connection: connection,
            isLowBattery: lowBattery,
            isLowPowerMode: lowPower
        )
    }

    // MARK: Renditions

    /// What `song` offers on this device: the rungs it lists, plus the original if its codec and size
    /// can be decoded here. A song with no variants offers the original only, and only if decodable.
    func renditions(for song: Song) -> VideoRenditions {
        Self.renditions(
            videoVariants: song.videoVariants,
            originalIsPlayable: capability.canDecode(song.videoSource)
        )
    }

    /// `videoVariants` is the wire string, `"480p.mp4,720p.mp4"`. A token that is not a known rung, or
    /// that could address a different file (a path separator, `..`), is ignored.
    static func renditions(videoVariants: String?, originalIsPlayable: Bool) -> VideoRenditions {
        var names: [VideoQuality: String] = [:]
        for token in (videoVariants ?? "").split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains("..") else { continue }
            let name = trimmed.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
            guard let quality = VideoQuality(rawValue: name), quality.isRung else { continue }
            names[quality] = trimmed
        }
        return VideoRenditions(variantFileNames: names, offersOriginal: originalIsPlayable)
    }

    // MARK: Decision

    /// The picture to play.
    ///
    /// - No variants: the original `videoFile`, whatever the preference ("as today"). The device may
    ///   not be able to decode it, but nothing else exists, and the player gives up cleanly on a file
    ///   that will not open.
    /// - Auto: on Wi-Fi the highest rung up to 1080p (never the original, which can be 4K); when
    ///   constrained the lowest rung.
    /// - An explicit choice: that quality, or the next lower one the song has. Original, when this
    ///   device cannot play it, becomes the best rung. A choice lower than every rung gets the lowest.
    static func choose(
        preference: VideoQuality,
        renditions: VideoRenditions,
        conditions: VideoQualityConditions
    ) -> VideoQualityChoice {
        let rungs = VideoQuality.rungs.filter { renditions.variantFileNames[$0] != nil }
        guard let lowest = rungs.first, let highest = rungs.last else { return .original }

        func choice(_ quality: VideoQuality) -> VideoQualityChoice {
            VideoQualityChoice(quality: quality, variantFileName: renditions.variantFileNames[quality])
        }

        switch preference {
        case .auto:
            return choice(conditions.isConstrained ? lowest : highest)
        case .original:
            return renditions.offersOriginal ? .original : choice(highest)
        case .p480, .p720, .p1080:
            let best = rungs.last { $0 <= preference } ?? lowest
            return choice(best)
        }
    }

    /// `choose` for a song, from the stored preference.
    func choice(for song: Song, conditions: VideoQualityConditions) -> VideoQualityChoice {
        Self.choose(preference: userSelectedQuality, renditions: renditions(for: song), conditions: conditions)
    }
}
