import Foundation

/// Ports `BatteryService.isLowBattery` (`lib/services/battery_service.dart`)
/// — T31's audio-quality plan cap is forced to `.low` when this is true,
/// regardless of the user's own quality preference.
protocol BatteryLevelMonitoring: Sendable {
    var isLowBattery: Bool { get async }
}
