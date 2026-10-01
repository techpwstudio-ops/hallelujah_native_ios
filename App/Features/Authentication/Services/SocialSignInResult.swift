/// What `GoogleSignInCoordinator`/`AppleSignInCoordinator` hand back once
/// the platform SDK's own sign-in sheet succeeds — the profile fields to
/// forward as `SocialAuthVerifyRequest.User`, plus the provider token
/// (`secrete`) that proves the sign-in to the backend.
struct SocialSignInResult: Sendable {
    let user: SocialAuthUser
    let secrete: String
}

/// Failures a coordinator can throw. `SocialAuthViewModel` catches these
/// per-provider, since Dart shows a different message/behaviour for each
/// (see that type's doc comment).
enum SocialAuthError: Error, Sendable {
    /// The SDK completed but produced no usable token — Apple's
    /// `identityToken` was nil/undecodable, or Google's ID token was nil,
    /// or no window was available to present from.
    case missingCredential
    /// The person dismissed the system sign-in sheet. Apple-only: Dart's
    /// `loginWithApple` special-cases `ASAuthorizationError.canceled` to
    /// return silently with no toast. `googleSignIn` has no equivalent
    /// special case, so `GoogleSignInCoordinator` never throws this.
    case canceled
}
