import GoogleSignIn
import UIKit

/// `googleSignIn` (`lib/blocs/auth/bloc.dart`) minus its
/// `FirebaseAuth.instance.signOut()`/`.signInWithCredential(...)` calls:
/// nothing in this app reads `FirebaseAuth.instance.currentUser` (confirmed
/// by grep — the only other call sites are in `auth_provider.dart`, all
/// commented-out legacy code), and the session this flow actually produces
/// comes entirely from `/auth/oauth/verify` below, so standing up a second,
/// unconsumed Firebase Auth session isn't ported.
///
/// No cancellation special-case, unlike `AppleSignInCoordinator`: Dart's
/// `googleSignIn()` catch block doesn't check for a cancel code either, so
/// any failure here — including the person dismissing the sheet — surfaces
/// through `SocialAuthViewModel`'s generic error branch, matching that.
@MainActor
final class GoogleSignInCoordinator {
    func signIn() async throws -> SocialSignInResult {
        guard let presenter = Self.presentingViewController() else {
            throw SocialAuthError.missingCredential
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

        guard let idToken = result.user.idToken?.tokenString else {
            // `_checkSocialAuth`'s `if (secrete == null)` guard — reached
            // here instead of there, since `SocialSignInResult.secrete`
            // isn't optional.
            throw SocialAuthError.missingCredential
        }

        // `user.displayName?.split(' ').first`/`.last` (Dart) — deliberately
        // the raw display name split on a space, not Google's own
        // given/family-name fields, to match that exact derivation.
        let displayName = result.user.profile?.name
        let nameParts: [Substring] = displayName?.split(separator: " ") ?? []
        let fName: String? = nameParts.first.map { String($0) }
        let lName: String? = nameParts.last.map { String($0) }

        let user = SocialAuthUser(
            name: displayName,
            email: result.user.profile?.email,
            // Dart's plugin exposes a single `photoUrl` with no size
            // parameter; `GIDGoogleUser` has no equivalent default, so a
            // size is picked explicitly here — 320pt covers every avatar
            // this app's design system renders, with headroom for @2x/@3x.
            image: result.user.profile?.imageURL(withDimension: 320)?.absoluteString,
            fName: fName,
            lName: lName
        )
        return SocialSignInResult(user: user, secrete: idToken)
    }

    private static func presentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
