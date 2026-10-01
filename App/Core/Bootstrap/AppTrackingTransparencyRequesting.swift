import AppTrackingTransparency

/// Native-only addition — the Flutter app never requests tracking
/// authorization (`Info.plist` has no `NSUserTrackingUsageDescription`, and
/// nothing in the Dart source touches App Tracking Transparency), so there's
/// no Dart behavior to match here. Requested from `SplashViewModel.start()`,
/// fire-and-forget: Apple's guidance is to ask once something is already on
/// screen to give the prompt context, not at process launch before any UI
/// exists, and a non-blocking request keeps it from delaying the splash.
///
/// Not `@MainActor`-isolated at the type level even though
/// `ATTrackingManager` wants to be called from the main thread: its only
/// call site is `SplashViewModel.start()`'s `Task { }`, which — since
/// `SplashViewModel` is itself `@MainActor` and the task isn't detached —
/// already inherits and runs on the main actor. Keeping this type plain
/// `Sendable` instead matches every other `DependencyContainer` registration
/// in `AppComposition` and avoids mixing isolated/nonisolated factory
/// closures in one composition root.
protocol AppTrackingTransparencyRequesting: Sendable {
    func requestAuthorization() async
}

struct SystemAppTrackingTransparencyRequester: AppTrackingTransparencyRequesting {
    func requestAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }
}
