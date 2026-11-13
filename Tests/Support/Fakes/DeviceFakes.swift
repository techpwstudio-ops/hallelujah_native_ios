import Foundation
@testable import Hallelujah

struct FakeBatteryMonitor: BatteryLevelMonitoring {
    var isLowBattery: Bool
}

struct FakeConnectivity: ConnectivityTypeProviding {
    var currentConnectionType: ConnectionType?
}

struct FakeLowPowerMode: LowPowerModeProviding {
    var isLowPowerModeEnabled: Bool
}
