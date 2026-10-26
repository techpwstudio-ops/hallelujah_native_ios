import Foundation
import Observation

/// Native port of `NetworkStatusBloc` (`lib/blocs/network/bloc.dart`),
/// folded together with the app-lifecycle wiring `InternetService`'s
/// `init()`/`suspend()`/`resume()` get from `launch_app.dart`'s
/// `didChangeAppLifecycleState`. One native type covers both rather than
/// splitting a service/bloc pair the way Dart does: nothing else in this
/// app talks to `ReachabilityMonitoring` directly, so there's no second
/// consumer that would justify keeping them separate.
///
/// Owned by `AppShellView` as `@State` and handed down via `.environment`,
/// same lifetime/DI shape as `AppNavigationCoordinator` — its lifetime is
/// the signed-in session's (T20-24 sign-out isn't wired yet, so today that's
/// "the app shell's lifetime").
///
/// `PlaybackAnalyticsRecorder` (T38) resolves its own independent
/// `ReachabilityMonitoring` instance for the analytics payload's
/// `network_state` field rather than sharing this one — it's a
/// composition-root-level singleton and this type is View-layer `@State`,
/// so there's no single shared instance to hand it. `ReachabilityMonitoring`'s
/// own registration already anticipates a second consumer this way.
@Observable
@MainActor
final class NetworkStatusStore {
    private(set) var isOffline = false

    private let monitor: any ReachabilityMonitoring
    private let analytics: any AnalyticsTracking
    private let bibleRepository: any BibleRepository
    private var started = false

    init(container: DependencyContainer = .current) {
        monitor = container.resolve()
        analytics = container.resolve()
        bibleRepository = container.resolve()
    }

    /// Call once from `AppShellView.onAppear` — the native proxy for where
    /// `launch_app.dart` calls `InternetService.instance.init()`, i.e. once
    /// a signed-in session is confirmed, not at process launch.
    func start() {
        guard !started else { return }
        started = true
        monitor.start { [weak self] online in
            self?.apply(online: online)
        }
    }

    /// Call from `\.scenePhase` → `.background`.
    func suspend() {
        monitor.suspend()
    }

    /// Call from `\.scenePhase` → `.active`.
    func resume() {
        monitor.resume()
    }

    private func apply(online: Bool) {
        let wasOffline = isOffline
        isOffline = !online
        // `InternetService._applyStatus` also feeds `onStatusChange`, which the
        // `/dashboard/init` retry (`ReconnectRetry`) listens to.
        ReachabilityBroadcast.shared.publish(online: online)

        // `NetworkStatusBloc`'s reconnect trigger: on `wasOffline &&
        // !nowOffline`, Dart calls `PlaybackEventSyncService().syncPendingData()`.
        guard wasOffline, !isOffline else { return }
        Task { await analytics.syncIfNeeded() }
        // Bible highlights/notes saved while offline.
        let bible = bibleRepository
        Task { await bible.flushPendingAnnotations() }
    }
}
