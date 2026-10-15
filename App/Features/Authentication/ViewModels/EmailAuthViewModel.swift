import Foundation
import Observation

/// Ported from `EmailAuthState` (`email_auth_state.dart`) — one case per Dart
/// subclass, same collapsing-into-one-enum shape as `PhoneAuthFlowState`.
///
/// No `fallbackChannel` here: that's genuinely phone-only in Dart
/// (`mobile_otp_unsupported`, "SMS can't reach this dial code, try email
/// instead") — email has no equivalent failure mode, and `EmailAuthErrorState`
/// never carried the field to begin with.
enum EmailAuthFlowState: Equatable {
    case initial
    case loading
    /// `email` is the server-normalised identifier (lower-cased) — same
    /// field Dart's `EmailOtpSentState` carries.
    case otpSent(email: String)
    case authSuccess(isNewUser: Bool, requiresAccountSetup: Bool)
    case error(message: String, code: String?)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message, _) = self { return message }
        return nil
    }
}

/// Ported from `EmailAuthBloc` (`email_auth_bloc.dart`) — same in-flight
/// guard, same reliance on the server-normalised identifier for verify.
/// Talks to T20's `AuthRepository` directly, same as `PhoneAuthViewModel`.
///
/// Unlike phone, Dart's email send/verify never pass a `requestId` to
/// `AuthOtpService` — confirmed by reading `EmailAuthRepository.sendOtp`/
/// `verifyOtp`, neither of which accepts or forwards one, even though the
/// shared transport supports it for both channels. Matched here by always
/// passing `requestID: nil`, not by inventing a reuse rule Dart's email path
/// doesn't have.
///
/// Owned by `AuthenticationView` as a single `@State` instance and handed
/// down to both `EmailAuthView` and `EmailOTPView`, mirroring
/// `PhoneAuthViewModel`'s own lifetime/sharing shape.
@MainActor
@Observable
final class EmailAuthViewModel {
    private(set) var state: EmailAuthFlowState = .initial
    private(set) var email: String?

    private var sendInFlight = false

    private let authRepository: any AuthRepository
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        authRepository = container.resolve()
    }

    /// [rawEmail] is whatever the user typed, untouched — the repository
    /// sends it as-is and the server normalises it, same as Dart never
    /// lower-casing before the call.
    func sendOTP(rawEmail: String, isResend: Bool = false) async {
        guard !sendInFlight else { return }
        sendInFlight = true
        defer { sendInFlight = false }

        state = .loading
        email = rawEmail

        do {
            let result = try await authRepository.sendOTP(identifier: rawEmail, resend: isResend, requestID: nil)
            email = result.identifier
            state = .otpSent(email: result.identifier)
        } catch let error as AuthOTPError {
            state = .error(message: error.message, code: error.code)
        } catch {
            logger.warning("send email OTP failed: \(error)")
            state = .error(message: UserFacingError.message(for: error), code: nil)
        }
    }

    /// `ClearEmailAuthErrorEvent` — drops back to `otpSent` so the OTP field
    /// stops showing the stale error once the user starts editing again.
    func clearError() {
        guard state.isError, let email else { return }
        state = .otpSent(email: email)
    }

    /// `EditEmailOtpEvent` — the OTP screen's "edit email" affordance.
    func editEmail() {
        state = .initial
    }

    func verifyOTP(code: String) async {
        guard let email else { return }
        state = .loading

        do {
            let outcome = try await authRepository.verifyOTP(identifier: email, otp: code, requestID: nil)
            state = .authSuccess(isNewUser: outcome.isNewUser, requiresAccountSetup: outcome.requiresAccountSetup)
        } catch let error as AuthOTPError {
            state = .error(message: error.message, code: error.code)
        } catch {
            logger.warning("verify email OTP failed: \(error)")
            state = .error(message: UserFacingError.message(for: error), code: nil)
        }
    }
}
