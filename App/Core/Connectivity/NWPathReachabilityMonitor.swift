import Foundation
import Network

/// `NWPathMonitor`-backed `ReachabilityMonitoring`. Ports the *shape* of
/// `InternetService._updateStatus`/`_verifyOfflineThenApply`/
/// `_hasRealInternet` (`lib/services/InternetService.dart`): trust an
/// "online" reading immediately, but verify a "not online" reading with a
/// real reachability probe before ever declaring the device offline, using
/// a monotonic token to discard a probe result made stale by a newer path
/// update arriving while it was in flight. That verification step exists in
/// Dart to fix a real, previously-shipped bug (`connectivity_plus` emitting
/// transient `none` readings during Wi-Fi↔cellular handoffs and post-sleep
/// wake); `NWPathMonitor` is documented to have the same class of transient
/// `.unsatisfied` blip during an interface handoff, so the same shape is
/// ported here rather than trusting `NWPath.status` directly.
///
/// One deliberate deviation from Dart's probe mechanism: Dart resolves DNS
/// only (`InternetAddress.lookup`); this issues a `HEAD` request instead.
/// Both are lightweight, timeout-bounded, and race the same two hosts (the
/// API host, falling back to a public host) — a `HEAD` response additionally
/// proves the TCP/TLS path actually works, not just that a resolver has a
/// cached DNS answer, which is a strictly stronger reachability signal than
/// Dart's own check. Behaviorally equivalent; implemented with
/// `URLSession`/`URLRequest` instead of a raw POSIX DNS call because that's
/// existing, already-verified API surface elsewhere in this codebase.
@MainActor
final class NWPathReachabilityMonitor: ReachabilityMonitoring {
    private nonisolated static let probeTimeout: TimeInterval = 3

    private let configuration: AppConfiguration
    private let monitorQueue = DispatchQueue(label: "today.hallelujah.reachability")

    private var monitor: NWPathMonitor?
    private var onChange: ((Bool) -> Void)?
    private var probeToken = 0

    private(set) var isOnline = true

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard monitor == nil else { return }
        self.onChange = onChange
        beginMonitoring()
    }

    func suspend() {
        monitor?.cancel()
        monitor = nil
        // Any probe already in flight is now for a cancelled generation —
        // bump the token so its result is discarded on arrival.
        probeToken &+= 1
    }

    func resume() {
        guard monitor == nil else { return }
        beginMonitoring()
    }

    /// `NWPathMonitor` is documented as one-shot: once `cancel()`-ed, a
    /// monitor can't be restarted, so `suspend()`/`resume()` tear down and
    /// recreate it rather than reusing one instance — unlike Dart's
    /// `connectivity_plus` stream subscription, which is cheap to
    /// cancel/resubscribe without discarding an underlying object.
    private func beginMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // `pathUpdateHandler` fires on `monitorQueue`, not the main
            // actor — hop over before touching any state, same pattern as
            // `DeepLinkService.dispatch`'s `Task { await handle(...) }`.
            Task { @MainActor in
                self?.handle(path)
            }
        }
        self.monitor = monitor
        monitor.start(queue: monitorQueue)
    }

    private func handle(_ path: NWPath) {
        probeToken &+= 1
        let token = probeToken

        if path.status == .satisfied {
            apply(true)
            return
        }

        Task {
            let reachable = await Self.hasRealInternet(configuration: configuration)
            // A newer path update (or a suspend()) arrived while probing —
            // discard this result.
            guard token == probeToken else { return }
            apply(reachable)
        }
    }

    private func apply(_ online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        onChange?(online)
    }

    /// Off the main actor on purpose — network I/O has no reason to run on
    /// it, and nothing here touches actor-isolated state (`configuration`
    /// is an immutable, already-`Sendable` value type).
    private nonisolated static func hasRealInternet(configuration: AppConfiguration) async -> Bool {
        let hosts = Set([configuration.apiBaseURL.host, "cloudflare.com"].compactMap { $0 })
        guard !hosts.isEmpty else { return false }

        return await withTaskGroup(of: Bool.self) { group in
            for host in hosts {
                group.addTask { await probe(host: host) }
            }
            for await reachable in group where reachable {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private nonisolated static func probe(host: String) async -> Bool {
        guard let url = URL(string: "https://\(host)/") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = probeTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }
}
