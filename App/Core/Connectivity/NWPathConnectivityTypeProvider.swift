import Foundation
import Network

/// `NWPathMonitor`-backed `ConnectivityTypeProviding`. Unlike
/// `NWPathReachabilityMonitor`, this runs its own monitor for the process's
/// whole lifetime rather than a `start()`/`suspend()`/`resume()` lifecycle
/// keyed to `scenePhase` — one lightweight kernel-backed path monitor is
/// cheap enough to just leave running, and nothing here does the
/// timeout-bounded network I/O (the reachability probe) that justified
/// pausing the other monitor while backgrounded.
actor NWPathConnectivityTypeProvider: ConnectivityTypeProviding {
    private let monitor = NWPathMonitor()
    private var latest: ConnectionType?

    var currentConnectionType: ConnectionType? { latest }

    init() {
        let monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let type = Self.classify(path)
            Task { await self?.apply(type) }
        }
        monitor.start(queue: DispatchQueue(label: "today.hallelujah.connectivity-type"))
    }

    private func apply(_ type: ConnectionType) {
        latest = type
    }

    private static func classify(_ path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}
