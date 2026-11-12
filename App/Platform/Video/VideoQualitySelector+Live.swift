import Foundation

extension VideoQualitySelector {
    /// The selector wired to the device's real battery, network, Low Power Mode and decoders.
    /// Building one starts a path monitor (see `NWPathConnectivityTypeProvider`), so build it once and
    /// share it; `VideoQualityStore` is that one place.
    @MainActor static func live(keyValueStore: any KeyValueStoring) -> VideoQualitySelector {
        VideoQualitySelector(
            keyValueStore: keyValueStore,
            batteryMonitor: UIDeviceBatteryLevelMonitor(),
            connectivityType: NWPathConnectivityTypeProvider(),
            lowPowerMode: ProcessInfoLowPowerModeProvider(),
            capability: .live
        )
    }
}
