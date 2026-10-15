import Foundation

/// Request body for `/auth/oauth/verify` — `_checkSocialAuth`'s request map
/// (`lib/blocs/auth/bloc.dart`). The response reuses `AuthOTPVerifyResponse`
/// as-is: same flat token/user/isNewUser/requiresAccountSetup envelope.
/// `languages` is the only field that response adds beyond what
/// `AuthOTPVerifyResponse` already models, and it's left unported for the
/// same reason `deviceId`/`membership`/`isPasswordSet` already are (see that
/// type's doc comment) — no native consumer exists yet.
///
struct SocialAuthVerifyRequest: Encodable, Sendable {
    struct User: Encodable, Sendable {
        let name: String?
        let email: String?
        let image: String?
        let fName: String?
        let lName: String?
    }

    struct Provider: Encodable, Sendable {
        let name: String
        /// Matches the server's actual field name (`provider.secrete`) —
        /// not a typo introduced by this port.
        let secrete: String
    }

    let user: User
    let secret1: String
    let secret2: String
    let appCheck: String?
    /// The one real call site (`SocialSignInButtons` in
    /// `authentication_page.dart`) always passes `isRegister: false`, so
    /// `isLogin` is always `true` there — hardcoded at the call site
    /// (`RemoteAuthRepository.verifySocialAuth`) rather than threaded as a
    /// parameter nothing yet needs to vary.
    let isLogin: Bool
    let provider: Provider
    /// `_getRefer()` — deep-link attribution (`ReferralAttributionStore`).
    var refer: ReferAttribution? = nil
}
