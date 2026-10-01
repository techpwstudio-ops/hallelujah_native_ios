import Foundation

/// Decides the *target* `AudioQuality` for the next thing played — not
/// which of that quality's encoded variants a given song actually has (see
/// `AudioSourceResolver` for that half). Ports `S3Service.effectiveAudioQuality`
/// (plan cap) combined with `streamableVariant` (network cap) via
/// `selectBestVariant`'s "stricter cap wins" rule (`s3_service.dart:31-34,
/// 129-176,148-176`).
struct AudioQualitySelector: Sendable {
    private static let userQualityKey = "audio.selectedQuality"

    private let keyValueStore: any KeyValueStoring
    private let batteryMonitor: any BatteryLevelMonitoring
    private let connectivityType: any ConnectivityTypeProviding

    init(
        keyValueStore: any KeyValueStoring,
        batteryMonitor: any BatteryLevelMonitoring,
        connectivityType: any ConnectivityTypeProviding
    ) {
        self.keyValueStore = keyValueStore
        self.batteryMonitor = batteryMonitor
        self.connectivityType = connectivityType
    }

    /// `OurSession.selectedAudioQuality`, default `.standard`. No Settings
    /// screen writes this key yet (Settings is a later milestone) — reading
    /// it here now means that screen only ever has to start writing it, with
    /// no engine-side change needed once it exists.
    var userSelectedQuality: AudioQuality {
        get async {
            keyValueStore.string(forKey: Self.userQualityKey).flatMap(AudioQuality.init(rawValue:)) ?? .standard
        }
    }

    func setUserSelectedQuality(_ quality: AudioQuality) {
        keyValueStore.setString(quality.rawValue, forKey: Self.userQualityKey)
    }

    /// `effectiveAudioQuality` × `streamableVariant`, combined the way
    /// `selectBestVariant` combines its two caps: take the stricter (lower)
    /// of the two, or the plan cap alone when there's no network reading yet.
    func targetQuality() async -> AudioQuality {
        let planCap: AudioQuality = if await batteryMonitor.isLowBattery {
            .low
        } else {
            await userSelectedQuality
        }
        guard let connectionType = await connectivityType.currentConnectionType else {
            return planCap
        }
        return min(planCap, Self.networkCap(for: connectionType))
    }

    /// `streamableVariant` (`analytics_tracking_data_utils.dart:129-136`).
    private static func networkCap(for connectionType: ConnectionType) -> AudioQuality {
        switch connectionType {
        case .wifi, .ethernet: .high
        case .cellular: .standard
        case .none: .low
        case .other: .standard
        }
    }
}
