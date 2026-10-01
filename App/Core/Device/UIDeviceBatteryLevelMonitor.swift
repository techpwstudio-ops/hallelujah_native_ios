import UIKit

/// `UIDevice.batteryLevel`-backed `BatteryLevelMonitoring`. Monitoring must
/// be enabled once before `batteryLevel` reports anything but `-1.0`
/// (`UIDevice`'s own precondition for that property) — enabled once here at
/// init and never disabled, since this type is expected to live for the
/// app's whole lifetime (DI-registered, same as `NWPathConnectivityTypeProvider`).
final class UIDeviceBatteryLevelMonitor: BatteryLevelMonitoring {
    /// Mirrors `BatteryService.lowBatteryThreshold` — 20%.
    private static let lowBatteryThresholdFraction: Float = 0.20

    @MainActor
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var isLowBattery: Bool {
        get async {
            await MainActor.run {
                let level = UIDevice.current.batteryLevel
                // `-1.0` = unknown (monitoring not yet settled, or no
                // battery — e.g. some simulators). Mirrors Dart's `_level
                // != null && ...`: an unreadable level never caps quality.
                return level >= 0 && level <= Self.lowBatteryThresholdFraction
            }
        }
    }
}
