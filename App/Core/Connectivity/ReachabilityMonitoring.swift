/// Native port of `InternetService`'s (`lib/services/InternetService.dart`)
/// public shape: a current `isOnline` reading, a status-change
/// notification, and an explicit start/suspend/resume lifecycle keyed to
/// app foreground/background transitions — Dart drives `suspend()`/
/// `resume()` from `didChangeAppLifecycleState`, the native equivalent
/// being `NetworkStatusStore` observing `\.scenePhase`.
///
/// `AnyObject`, not `Sendable`: every conformer here is `@MainActor`-scoped
/// top to bottom (state, callback delivery, everything), matching
/// `AppNavigationCoordinator`/`SplashViewModel`'s own un-Sendable
/// MainActor-class shape — unlike `ClockProviding`/`CrashReporting`/etc.,
/// nothing needs to call this from off the main actor.
protocol ReachabilityMonitoring: AnyObject {
    /// Defaults `true` until a status is confirmed, mirroring Dart's
    /// `isOnline => _isOnline ?? true` ("assume online until confirmed
    /// offline").
    var isOnline: Bool { get }

    /// Begins monitoring and delivers every status change, including the
    /// first one, on the main actor. Calling this again before `suspend()`
    /// is a no-op — mirrors Dart's `if (_sub != null) return` guard in
    /// `init()`.
    func start(onChange: @escaping (Bool) -> Void)

    /// Stops monitoring and invalidates any in-flight reachability probe so
    /// a late result can't apply a stale status after resuming. Call from
    /// `scenePhase` → `.background`.
    func suspend()

    /// Resumes monitoring after a `suspend()`. Call from `scenePhase` →
    /// `.active`. `NWPathMonitor` delivers a fresh status the moment it
    /// (re)starts, so — unlike Dart's `resume()`, which has to explicitly
    /// call `checkConnectivity()` — there's no separate manual re-check step
    /// to write here.
    func resume()
}
