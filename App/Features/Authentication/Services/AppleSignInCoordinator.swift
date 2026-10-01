import AuthenticationServices
import CryptoKit
import UIKit

/// `loginWithApple` (`lib/blocs/auth/bloc.dart`) — bridges
/// `ASAuthorizationController`'s delegate-based flow to async/await.
///
/// Not `@MainActor` at the type level: `ASAuthorizationControllerDelegate`/
/// `ASAuthorizationControllerPresentationContextProviding` are `@objc`
/// protocols whose requirements are nonisolated, and Swift 6 rejects a
/// main-actor-isolated method satisfying a nonisolated `@objc` requirement.
/// Only `signIn()` needs the main actor, to build and present the
/// controller; the delegate callbacks below are always invoked on the main
/// thread by AuthenticationServices regardless of the method's own
/// isolation, so reading `UIApplication.shared` through
/// `MainActor.assumeIsolated` in `presentationAnchor(for:)` is safe — the
/// documented escape hatch for exactly this situation. `@unchecked
/// Sendable` covers handing `self` to the controller as its delegate/
/// presentation-context provider across that boundary; the only mutable
/// state (`continuation`) is written from those same always-main-thread
/// callbacks and read only once per `signIn()` call.
final class AppleSignInCoordinator: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<SocialSignInResult, Error>?
    /// Held as a property, not a local in `signIn()`: `ASAuthorizationController.
    /// delegate` is `weak`, so nothing else keeps this alive across the
    /// system sign-in sheet's lifetime — a local `let` here risks ARC
    /// deallocating it before its delegate ever fires.
    private var controller: ASAuthorizationController?

    @MainActor
    func signIn() async throws -> SocialSignInResult {
        let rawNonce = Self.generateNonce()
        let hashedNonce = Self.sha256(rawNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        // `_sha256ofString(_generateNonce())` — the HASHED value goes to
        // Apple; Dart never separately forwards the raw nonce to the
        // backend (`_checkSocialAuth` only sends `identityToken`), so
        // neither does this.
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    /// `_generateNonce` (`lib/blocs/auth/bloc.dart`) — identical charset and
    /// default length (32).
    private static func generateNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    /// `_sha256ofString` — lowercase hex, same as `sha256.convert(...)
    /// .toString()`.
    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            // `if (res.identityToken == null) { showSnackBarToast(message:
            // "Apple sign-in failed. Please try again."); return false; }`
            resume(throwing: SocialAuthError.missingCredential)
            return
        }

        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
        let fullName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")

        let user = SocialAuthUser(
            name: fullName,
            email: credential.email,
            image: nil,
            fName: credential.fullName?.givenName,
            lName: credential.fullName?.familyName
        )
        resume(returning: SocialSignInResult(user: user, secrete: identityToken))
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // `e is SignInWithAppleAuthorizationException && e.code ==
        // AuthorizationErrorCode.canceled` — the one exception Dart lets
        // through with no toast.
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            resume(throwing: SocialAuthError.canceled)
            return
        }
        resume(throwing: error)
    }

    private func resume(returning result: SocialSignInResult) {
        continuation?.resume(returning: result)
        continuation = nil
        controller = nil
    }

    private func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        controller = nil
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
