import Foundation

extension AudioQualitySelector {
    /// The selector wired to the device's real battery and network monitors.
    /// `AudioQualitySelector` is stateless (everything lives in
    /// `keyValueStore`), so call sites that need an effective quality — the
    /// player's download button, the song menu — build one on demand instead
    /// of sharing an instance.
    @MainActor static func live(keyValueStore: any KeyValueStoring) -> AudioQualitySelector {
        AudioQualitySelector(
            keyValueStore: keyValueStore,
            batteryMonitor: UIDeviceBatteryLevelMonitor(),
            connectivityType: NWPathConnectivityTypeProvider()
        )
    }
}
