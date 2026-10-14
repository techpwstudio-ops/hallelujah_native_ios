import Foundation
import Observation

/// Ported from `PhoneAuthState` (`phone_auth_state.dart`) — one case per
/// Dart subclass, collapsed into a single enum since Swift has no sealed-class
/// state-machine idiom as lightweight as Bloc's.
enum PhoneAuthFlowState: Equatable {
    case initial
    case loading
    /// `mobile` is the server-normalised identifier (E.164, formatting
    /// stripped) — same field Dart's `OtpSentState` carries.
    case otpSent(mobile: String)
    case authSuccess(isNewUser: Bool, requiresAccountSetup: Bool)
    case error(message: String, code: String?, fallbackChannel: String?)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message, _, _) = self { return message }
        return nil
    }
}

/// Ported from `PhoneAuthBloc` (`phone_auth_bloc.dart`) — same request-id
/// reuse rule, same in-flight guard, same reliance on the server-normalised
/// identifier for verify. Talks to T20's `AuthRepository` directly (there is
/// no native `PhoneAuthRepository`/`AuthOtpService` split to mirror: both
/// Dart classes funnel through the identical unified OTP transport, which
/// `RemoteAuthRepository` already implements in one place).
///
/// Owned by `AuthenticationView` as a single `@State` instance and handed
/// down to both `PhoneAuthView` and `OTPView` — the same "one bloc instance
/// shared with the OTP screen via navigation arguments" shape as Dart's
/// `PhoneAuthScreen` passing its `phoneAuthBloc` through
/// `NavigationService.to`'s `arguments`.
@MainActor
@Observable
final class PhoneAuthViewModel {
    private(set) var state: PhoneAuthFlowState = .initial

    /// The number as the SERVER normalised it — what `verifyOTP` must send,
    /// since the OTP is keyed by that value. Kept separately from the raw
    /// text passed into `sendOTP` for the same reason Dart keeps
    /// `_lastRequestedRaw` apart from `phoneNumber`.
    private(set) var phoneNumber: String?

    private var lastRequestedRaw: String?
    private var requestID: String?
    private var sendInFlight = false

    private let authRepository: any AuthRepository
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        authRepository = container.resolve()
    }

    /// [rawPhoneNumber] is the full E.164 string (`"\(dialCode)\(digits)"`) —
    /// callers build that, this just sends it. A fresh `requestID` is minted
    /// only when the number actually changed since the last send, so a resend
    /// of the same number reuses the same code request the way Dart's
    /// `_lastRequestedRaw` comparison does.
    func sendOTP(rawPhoneNumber: String, isResend: Bool = false) async {
        guard !sendInFlight else { return }
        sendInFlight = true
        defer { sendInFlight = false }

        state = .loading

        if lastRequestedRaw != rawPhoneNumber || requestID == nil {
            requestID = UUID().uuidString
        }
        lastRequestedRaw = rawPhoneNumber
        phoneNumber = rawPhoneNumber

        do {
            let result = try await authRepository.sendOTP(identifier: rawPhoneNumber, resend: isResend, requestID: requestID)
            phoneNumber = result.identifier
            state = .otpSent(mobile: result.identifier)
        } catch let error as AuthOTPError {
            state = .error(message: error.message, code: error.code, fallbackChannel: error.fallbackChannel)
        } catch {
            logger.warning("send OTP failed: \(error)")
            state = .error(message: error.localizedDescription, code: nil, fallbackChannel: nil)
        }
    }

    /// `ClearPhoneAuthErrorEvent` — drops back to `otpSent` so the OTP field
    /// stops showing the stale error once the user starts editing again.
    func clearError() {
        guard state.isError, let phoneNumber else { return }
        state = .otpSent(mobile: phoneNumber)
    }

    /// `EditPhoneAuthEvent` — the OTP screen's "edit number" affordance.
    func editPhoneNumber() {
        state = .initial
        lastRequestedRaw = nil
        requestID = nil
    }

    func verifyOTP(code: String) async {
        guard let phoneNumber, let requestID else { return }
        state = .loading

        do {
            let outcome = try await authRepository.verifyOTP(identifier: phoneNumber, otp: code, requestID: requestID)
            state = .authSuccess(isNewUser: outcome.isNewUser, requiresAccountSetup: outcome.requiresAccountSetup)
        } catch let error as AuthOTPError {
            state = .error(message: error.message, code: error.code, fallbackChannel: error.fallbackChannel)
        } catch {
            logger.warning("verify OTP failed: \(error)")
            state = .error(message: error.localizedDescription, code: nil, fallbackChannel: nil)
        }
    }
}
