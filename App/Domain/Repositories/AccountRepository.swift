import Foundation

/// Ports the account-deletion half of `AuthBloc.delete` (`bloc.dart:395-418`)
/// — the confirmation dialogs and biometric gate that precede this call stay
/// in `AccountDeletionView`/its view model (T71); this repository is only
/// the network call plus the sign-out cascade, mirroring how
/// `RemoteAuthRepository.logout()` bundles its own network call with
/// `session.logout()`/`currentUserStore.clear()`.
protocol AccountRepository: Sendable {
    /// `EndPoints.deleteUserDataApi` (`/users/account/request/delete`) —
    /// schedules deletion 7 days out and blacklists the caller's access
    /// token server-side; it does not delete synchronously. On a 200
    /// response this also runs the same sign-out teardown
    /// `RemoteAuthRepository.logout()` does (`session.logout()` +
    /// `currentUserStore.clear()`), which is what actually satisfies T71's
    /// "signs the user out" done-criterion — `SignOutSignal`'s own doc
    /// comment confirms `RootView` reacts to that teardown for ANY reason,
    /// so no separate navigation call is needed here, matching Dart's
    /// `NavigationService.offAll(AuthenticationPage.routeName)` via the
    /// native app's own existing equivalent mechanism instead of a second,
    /// bespoke one.
    ///
    /// Throws only on a transport failure. A non-200 HTTP response (e.g. the
    /// real backend's documented 403 "Account already has deletion
    /// scheduled") is returned as `succeeded: false` with the server's own
    /// message, matching `AuthBloc.delete`'s unconditional
    /// `showSnackBarToast(message: body['message'])` BEFORE its
    /// `if (res.statusCode == 200)` branch — Dart shows that message either
    /// way, and only signs out on the 200 path.
    func deleteAccount(reason: String) async throws -> AccountDeletionResult
}

struct AccountDeletionResult: Sendable {
    let succeeded: Bool
    let message: String
}
