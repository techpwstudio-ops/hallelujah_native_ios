/// The profile fields Google/Apple hand back after sign-in, forwarded to
/// `/auth/oauth/verify` as `_checkSocialAuth`'s `user` map
/// (`lib/blocs/auth/bloc.dart`) does. Every field is optional because Dart's
/// `UserModel.toJson()` drops null keys entirely rather than sending
/// `null` — `SocialAuthVerifyRequest`'s synthesized `Encodable` conformance
/// (`App/Data/DTOs/SocialAuthDTOs.swift`) reproduces that same
/// omit-if-absent behaviour for free.
struct SocialAuthUser: Sendable, Equatable {
    let name: String?
    let email: String?
    let image: String?
    let fName: String?
    let lName: String?
}

/// `AuthProvideTypes` (`lib/models/...`) minus `facebook` — no native UI
/// ever calls into a Facebook coordinator (see `SocialSignInButtonsView`'s
/// doc comment), so it isn't modeled here.
enum SocialAuthProvider: String, Sendable {
    case google
    case apple
}
