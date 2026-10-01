import Foundation

/// Bridges `Session`'s actor-isolated `onLogout` callback into SwiftUI, so
/// `RootView` can react the instant a session ends for ANY reason — an
/// explicit `AuthRepository.logout()` call, or `Session.refreshIfNeeded()`
/// silently logging out after a refresh-token failure (already live: any
/// authenticated `HTTPClient.send` that gets a 401 triggers this today, per
/// `HTTPClient`'s doc comment).
///
/// This is the native shape of what T26's roadmap text calls "auth-required
/// gates". Dart doesn't need a separate mechanism for this: `session.dart`'s
/// `logout()` just calls `NavigationService.offAll(AuthenticationPage
/// .routeName)` imperatively, forcing the nav stack back to sign-in from
/// wherever it was. `RootView`'s `switch launchViewModel.destination`
/// resolves once and never revisits itself, so without this bridge a
/// same-session sign-out (once `AppShellView` has real screens making real
/// calls, M5+) would silently strand the UI on stale content with no
/// tokens/user behind it. Confirmed via full-app grep there is no separate
/// per-route auth guard in `app_router.dart` to port — this redirect-on-
/// sign-out IS the entire mechanism, matching Dart's.
///
/// `Session.setOnLogout` is a single-callback seam (T20/T24) — this is
/// notified from the SAME closure `AppComposition` already registers to
/// clear `CurrentUserStore`, not a second registration. Any future
/// subsystem (player, library, downloads, WebSocket — all M5+) that needs
/// its own logout teardown should extend that one closure too, not call
/// `setOnLogout` again — it would silently replace this registration.
@MainActor
@Observable
final class SignOutSignal: Sendable {
    /// Increments on every sign-out. A counter, not a `Bool`, so two
    /// sign-outs in a row (unlikely, but e.g. a 401 during the brief window
    /// after an explicit logout's own request is in flight) each still
    /// produce an observable change for `.onChange` to catch.
    private(set) var generation = 0

    func notify() {
        generation += 1
    }
}
