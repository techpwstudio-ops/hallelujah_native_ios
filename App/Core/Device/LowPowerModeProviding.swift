import Foundation

/// Whether the listener has turned on Low Power Mode. `VideoQualitySelector` drops "Auto" to the
/// smallest picture while it is on, the same way it does on a low battery.
protocol LowPowerModeProviding: Sendable {
    var isLowPowerModeEnabled: Bool { get async }
}

/// The system's own switch.
struct ProcessInfoLowPowerModeProvider: LowPowerModeProviding {
    var isLowPowerModeEnabled: Bool {
        get async { ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
