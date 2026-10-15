import Foundation
import Observation

/// Mirrors the state shape `EmailAuthFlowState`/the phone equivalent use —
/// no `otpSent` case here since there's no OTP step, only a single round
/// trip through the platform SDK and `/auth/oauth/verify`.
enum SocialAuthFlowState: Equatable {
    case idle
    case loading
    case success(isNewUser: Bool, requiresAccountSetup: Bool)
    case error(message: String)
}

/// `AuthBloc.googleSignIn`/`.loginWithApple`
/// (`lib/blocs/auth/bloc.dart`) — owns the two platform coordinators and the
/// `/auth/oauth/verify` round trip that finalises the session on success.
///
/// The two sign-in methods below deliberately don't share their `catch`
/// blocks: Dart's own `googleSignIn`/`loginWithApple` each show different
/// messages for what is structurally the same failure (missing credential,
/// generic error), and don't treat cancellation the same way either — see
/// `SocialAuthError`'s doc comment. Collapsing them into one shared path
/// would lose that distinction rather than simplify anything.
///
/// `_checkIfTester`'s 405-status "flash screen" branch isn't ported — no
/// `FlashScreen` equivalent exists natively, and it's an internal testing
/// affordance orthogonal to the sign-in flow itself.
@MainActor
@Observable
final class SocialAuthViewModel {
    private(set) var state: SocialAuthFlowState = .idle

    private let authRepository: any AuthRepository
    private let googleCoordinator = GoogleSignInCoordinator()
    private let appleCoordinator = AppleSignInCoordinator()
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        authRepository = container.resolve()
    }

    func signInWithGoogle() async {
        state = .loading
        do {
            let result = try await googleCoordinator.signIn()
            try await verify(result: result, provider: .google)
        } catch SocialAuthError.missingCredential {
            state = .error(message: String(localized: "Authentication with google failed, please try another method"))
        } catch {
            logger.warning("google sign-in failed: \(error)")
            state = .error(message: String(localized: "Google sign-in did not complete. Please try again."))
        }
    }

    func signInWithApple() async {
        state = .loading
        do {
            let result = try await appleCoordinator.signIn()
            try await verify(result: result, provider: .apple)
        } catch SocialAuthError.canceled {
            state = .idle
        } catch SocialAuthError.missingCredential {
            state = .error(message: String(localized: "Apple sign-in failed. Please try again."))
        } catch {
            logger.warning("apple sign-in failed: \(error)")
            state = .error(message: String(localized: "Apple sign-in did not complete. Please try again."))
        }
    }

    private func verify(result: SocialSignInResult, provider: SocialAuthProvider) async throws {
        do {
            let outcome = try await authRepository.verifySocialAuth(
                user: result.user,
                provider: provider,
                secrete: result.secrete
            )
            state = .success(isNewUser: outcome.isNewUser, requiresAccountSetup: outcome.requiresAccountSetup)
        } catch let error as AuthOTPError {
            state = .error(message: error.message)
        } catch {
            logger.warning("social auth verify failed: \(error)")
            state = .error(message: UserFacingError.message(for: error))
        }
    }
}
