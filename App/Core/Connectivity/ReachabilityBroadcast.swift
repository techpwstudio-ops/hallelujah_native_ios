import Foundation

/// `InternetService.onStatusChange` / `InternetService.isOnline`
/// (`lib/services/InternetService.dart`) as the app-wide broadcast non-View
/// code (the `/dashboard/init` retry, `ReconnectRetry`) listens to.
///
/// `NetworkStatusStore` owns the one live `ReachabilityMonitoring` instance
/// and is View-layer `@State`, so services can't reach it directly; it
/// publishes every confirmed online/offline change here instead. Like Dart's
/// `isOnline` ("assume online until confirmed offline") the initial value is
/// `true`.
@MainActor
final class ReachabilityBroadcast {
    static let shared = ReachabilityBroadcast()

    private(set) var isOnline = true
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    private init() {}

    func publish(online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        for continuation in continuations.values {
            continuation.yield(online)
        }
    }

    /// For an action that only works online and leaves nothing on screen to say
    /// so (handing a web page to Safari). Offline it shows the app's "No
    /// internet connection" toast and returns `false`.
    func requireOnline() -> Bool {
        guard !isOnline else { return true }
        ToastCenter.shared.show(UserFacingError.offline)
        return false
    }

    /// A stream of subsequent changes. Terminating it (cancelling the
    /// consuming task) unregisters the listener.
    func changes() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }
}
