import Foundation
import Observation

/// Ports `_FlashScreenState._initAuthAndNavigate()` /
/// `_resolveDestination()` (`lib/views/launch/flash.dart`).
///
/// Dropped from the Dart version, deliberately: `AnalyticsTrackingDataUtils()
/// .init()` / screen-view tracking — no FirebaseAnalytics event pipeline is
/// wired yet (declared as a T15 dependency, wired in T38).
///
/// One simplification the two-destination model used to buy, now closed by
/// T24: Dart's `_resolveDestination` returns `null` when `refreshIfNeeded()`
/// already logged out and navigated away out-of-band, and the caller has to
/// check for that. Here, `Session.logout()` clears the stored tokens
/// synchronously as part of that same failure path (and — since T24 wires
/// `Session.setOnLogout` in `AppComposition` — clears `CurrentUserStore` too),
/// so re-checking `currentAccessToken()`/`currentUserStore.user` after the
/// refresh attempt is sufficient — no separate "someone already navigated"
/// signal is needed.
@Observable
@MainActor
final class SplashViewModel {
    private(set) var destination: LaunchDestination?
    private(set) var availableUpdate: AppStoreVersionInfo?

    /// Matches `_minSplashDuration` — the branded logo animation must play in
    /// full every time the app opens from a killed state, regardless of how
    /// fast the session check below resolves.
    private static let minimumDuration: Duration = .seconds(2)
    /// Matches `_resolveDestination`'s `.timeout(const Duration(seconds: 6))`
    /// around `refreshIfNeeded()` — a slow network can never hold the splash
    /// past this.
    private static let refreshTimeout: Duration = .seconds(6)

    private let session: Session
    private let currentUserStore: CurrentUserStore
    private let authRepository: any AuthRepository
    private let versionChecker: any AppStoreVersionChecking
    private let trackingRequester: any AppTrackingTransparencyRequesting
    private let realtimeConnectionManager: RealtimeConnectionManager
    private let logger = AppLogger(category: .launch)

    init(container: DependencyContainer = .current) {
        session = container.resolve()
        currentUserStore = container.resolve()
        authRepository = container.resolve()
        versionChecker = container.resolve()
        trackingRequester = container.resolve()
        realtimeConnectionManager = container.resolve()
    }

    /// Runs the minimum-duration timer concurrently with destination
    /// resolution, same as Dart's `minDurationTimer` / `_resolveDestination`
    /// pair — the session check never makes the splash slower than the logo
    /// animation already is on its own. The version check and ATT prompt are
    /// fire-and-forget and never gate navigation.
    func start() async {
        logger.debug("splash: resolving launch destination")
        Task { self.availableUpdate = await self.versionChecker.checkForUpdate() }
        Task { await self.trackingRequester.requestAuthorization() }

        async let resolved = resolveDestination()
        try? await Task.sleep(for: Self.minimumDuration)
        let resolvedDestination = await resolved
        logger.debug("splash: resolved to \(resolvedDestination)")
        destination = resolvedDestination
    }

    private func resolveDestination() async -> LaunchDestination {
        guard await session.currentAccessToken() != nil, let cachedUser = await currentUserStore.user else {
            return .authentication
        }

        if await session.isAccessTokenExpired() {
            await refreshWithTimeout()
            // Re-checks both, not just the token: `refreshIfNeeded()`'s
            // internal `logout()` clears `CurrentUserStore` too (via the
            // `onLogout` hook `AppComposition` wires up), so either going nil
            // means the refresh failed and routed to auth out-of-band.
            guard await session.currentAccessToken() != nil, await currentUserStore.user != nil else {
                return .authentication
            }
        }

        // `unawaited(session.fetchUserDetails(background: true))` — verifies
        // account status and refreshes the cached user/membership without
        // blocking startup; `fetchCurrentUser()` already logs out on a
        // 403/404 the same way, so a deleted/blocked account is still caught.
        Task { try? await self.authRepository.fetchCurrentUser() }

        // T67 — mirrors Dart's cold-start `WebSocketService.instance.init(token)`:
        // a valid cached session reconnects the socket without blocking startup.
        Task { await self.realtimeConnectionManager.connect() }

        return cachedUser.needsAccountSetup ? .accountSetup : .app
    }

    func dismissAvailableUpdate() {
        availableUpdate = nil
    }

    /// `AuthenticationPage._navigateToNextScreen` — the OTP/social flow just
    /// finished and handed back whether the account still owes setup.
    func handleAuthenticationSuccess(requiresAccountSetup: Bool) {
        destination = requiresAccountSetup ? .accountSetup : .app
    }

    /// `AccountSetupPageState._finishLanguages` reaching
    /// `NavigationService.offAll(DashBoardContainer.routeName)`.
    func handleAccountSetupComplete() {
        destination = .app
    }

    /// T26 — `RootView` calls this when `SignOutSignal` fires, forcing the
    /// UI back to the sign-in flow from wherever it currently is. Matches
    /// `session.dart`'s `logout()` reaching
    /// `NavigationService.offAll(AuthenticationPage.routeName)`
    /// unconditionally, regardless of what screen was on top.
    ///
    /// No-ops while `destination` is still `nil`: a cold launch with a
    /// stale token whose refresh also fails can fire `SignOutSignal` from
    /// inside `resolveDestination()`'s own `refreshWithTimeout()` call,
    /// before `start()` has set `destination` for the first time.
    /// `resolveDestination()` already re-checks the token/user after that
    /// call and resolves straight to `.authentication` itself (see its own
    /// doc comment), so reacting here too would only risk cutting the
    /// splash's minimum-duration animation short for no benefit.
    func handleSignedOut() {
        guard destination != nil else { return }
        destination = .authentication
    }

    private func refreshWithTimeout() async {
        // Captures the actor (`Session`, unconditionally `Sendable`) rather
        // than `self` — `addTask`'s closure has to be `@Sendable`, and this
        // sidesteps needing `SplashViewModel` itself to be.
        let session = self.session
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await session.refreshIfNeeded()
            }
            group.addTask {
                try? await Task.sleep(for: Self.refreshTimeout)
            }
            await group.next()
            group.cancelAll()
        }
    }
}
