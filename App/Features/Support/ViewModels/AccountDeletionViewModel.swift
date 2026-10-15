import Foundation
import LocalAuthentication
import Observation

/// The two outcomes `_onDeletePressed`/`AuthBloc.delete` (`bloc.dart:395-424`)
/// distinguish for the final API call — same "keep the fixed transport-error
/// string separate from the server's own message" shape `FeedbackSubmitOutcome`
/// already draws for the sibling Feedback flow. Unlike that enum, a non-200
/// response isn't its own case here: Dart shows `body['message']`
/// unconditionally, before it even looks at the status code, so `succeeded`
/// only decides whether anything else needs to happen — not which message is
/// shown.
enum AccountDeletionOutcome: Equatable {
    case response(succeeded: Bool, message: String)
    case transportError
}

/// Step B's two possible results — `checkLocalAuth(allowAutoAuth: true)`
/// (`local_auth.dart`) either lets the flow continue (optionally after
/// showing its own "no device lock" toast) or blocks it outright with no
/// message at all. See `checkBiometricGate()`'s doc comment for the full
/// mapping this ports.
enum BiometricGateResult: Equatable {
    case passed(toastMessage: String?)
    case blocked
}

/// Ports the account-deletion half of `AuthBloc.delete` (`bloc.dart:395-424`)
/// plus `checkLocalAuth` (`local_auth.dart`): the biometric/device-auth gate
/// and the final network call. The confirmation dialogs themselves
/// (`showConfirmationDialog`/`showDeleteConfirmationDialog`) stay in
/// `AccountDeletionView` since they're `@State`-driven `.alert` presentation,
/// not business logic — same view/view-model split `FeedbackViewModel`
/// already draws for reason selection vs. the submit call itself.
@MainActor
@Observable
final class AccountDeletionViewModel {
    private(set) var isDeleting = false

    private let accountRepository: any AccountRepository
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        accountRepository = container.resolve()
    }

    /// Ports `checkLocalAuth(allowAutoAuth: true)` (`local_auth.dart`)
    /// exactly, including its deliberately permissive shape:
    ///
    /// - `canCheckBiometrics` false (no passcode/biometrics enrolled at all)
    ///   -> Dart's `if (!res) { toast(...); return allowAutoAuth; }`. Native's
    ///   closest equivalent of "can this device even attempt the check" is
    ///   `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication, error:)`
    ///   returning `false`. `allowAutoAuth` is always `true` at this one call
    ///   site (`_onDeletePressed`), so this always resolves to `.passed`.
    /// - Otherwise, Dart calls `authenticate(...)`; native calls
    ///   `evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)`,
    ///   bridged from its completion-handler shape to `async`/`await` with
    ///   `withCheckedContinuation` since `LAContext` predates Swift
    ///   concurrency (same bridging shape as
    ///   `SystemAppTrackingTransparencyRequester`).
    ///   - `success == true` -> Dart's `if (res) return true;` -> `.passed`,
    ///     no toast.
    ///   - `success == false` with the user having actually engaged a real
    ///     prompt and explicitly failed/cancelled it (`.userCancel`,
    ///     `.userFallback`, `.authenticationFailed`, `.systemCancel`) ->
    ///     Dart's bare `return false;` after a clean (non-`throw`ing)
    ///     `authenticate` call -> `.blocked`, no toast.
    ///   - `success == false` with any other error (no hardware, not
    ///     enrolled, lockout, no passcode set, or anything unexpected) ->
    ///     Dart's `catch` block, which returns `allowAutoAuth` (`true`) and
    ///     suppresses its own toast specifically because `allowAutoAuth` is
    ///     `true` here -> `.passed`, no toast.
    ///
    /// The asymmetry — a clean, explicit user rejection blocks deletion, but
    /// any inability to even attempt the check (simulator, no hardware, a
    /// transient error) lets it through silently — is intentional in Dart and
    /// preserved as-is; it is not strengthened or weakened here.
    func checkBiometricGate() async -> BiometricGateResult {
        let context = LAContext()
        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            return .passed(toastMessage: String(localized: "Your device does not have device lock, please set and try again"))
        }

        let blockingCodes: Set<LAError.Code> = [.userCancel, .userFallback, .authenticationFailed, .systemCancel]

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Please verify your identity to continue")
            ) { success, error in
                if success {
                    continuation.resume(returning: .passed(toastMessage: nil))
                    return
                }
                if let laError = error as? LAError, blockingCodes.contains(laError.code) {
                    continuation.resume(returning: .blocked)
                } else {
                    continuation.resume(returning: .passed(toastMessage: nil))
                }
            }
        }
    }

    /// Step D — `EndPoints.deleteUserDataApi` via `AuthBloc.delete`. Only
    /// guards re-entrancy (a double-tap while already in flight); `reason` is
    /// assumed already validated/finalized by the caller, matching
    /// `FeedbackViewModel.submit`'s same defensive-backstop shape. Returns
    /// `nil` for that no-op case.
    ///
    /// On `succeeded == true` the repository has already run
    /// `session.logout()`/`currentUserStore.clear()` internally (see
    /// `AccountRepository`'s own doc comment) — nothing further happens here;
    /// `SignOutSignal`'s app-wide observer redirects the whole app, so this
    /// view neither signs out nor navigates itself.
    func deleteAccount(reason: String) async -> AccountDeletionOutcome? {
        guard !isDeleting else { return nil }
        isDeleting = true
        defer { isDeleting = false }

        do {
            let result = try await accountRepository.deleteAccount(reason: reason)
            return .response(succeeded: result.succeeded, message: result.message)
        } catch {
            logger.warning("delete account failed: \(error)")
            return .transportError
        }
    }
}
