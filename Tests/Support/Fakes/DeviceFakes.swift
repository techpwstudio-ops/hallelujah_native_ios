import Foundation
@testable import GHallelujah

struct FakeBatteryMonitor: BatteryLevelMonitoring {
    var isLowBattery: Bool
}

struct FakeConnectivity: ConnectivityTypeProviding {
    var currentConnectionType: ConnectionType?
}
