/// Ports the unified OTP sign-in transport (`AuthOtpService`,
/// `lib/features/authentication/data/auth_otp_service.dart`) shared by both
/// `EmailAuthRepository` and `PhoneAuthRepository` in Dart — channel-agnostic
/// here too, so T21 (phone)/T22 (email) each add their own thin
/// repository/UI wiring on top rather than duplicating this transport.
///
/// No separate "register": the server classifies the identifier and, at
/// verify time, either resumes the account or creates it —
/// `AuthVerifyOutcome.isNewUser` says which one happened; there is no
/// separate register call to make.
protocol AuthRepository: Sendable {
    /// `AuthOtpService.send`/`.resend` — `resend` routes to the resend
    /// endpoint, which re-delivers the code already sent rather than minting
    /// a new one. Pass the SAME `requestID` to `verifyOTP` so two devices
    /// signing in with the same identifier can't consume each other's code.
    func sendOTP(identifier: String, resend: Bool, requestID: String?) async throws -> AuthOTPSendResult

    /// `AuthOtpService.verify`. On success this also finalizes the session —
    /// stores tokens, caches the user, and re-confirms the account still
    /// exists via `fetchCurrentUser()` — mirroring
    /// `AuthBloc.performUpdateAuth` plus the `fetchUserDetails()` call it
    /// makes before returning.
    func verifyOTP(identifier: String, otp: String, requestID: String?) async throws -> AuthVerifyOutcome

    /// `_checkSocialAuth` (`lib/blocs/auth/bloc.dart`) — Google/Apple
    /// sign-in verification. Reuses the same session-finalising shape as
    /// `verifyOTP`: on success this also stores tokens, caches the user, and
    /// re-confirms the account via `fetchCurrentUser()`.
    func verifySocialAuth(user: SocialAuthUser, provider: SocialAuthProvider, secrete: String) async throws -> AuthVerifyOutcome

    /// `AccountSetupPageState._submitDetails` (T24) — saves the account-setup
    /// details step and returns the refreshed `User`, same
    /// decode-then-cache shape as `fetchCurrentUser()` (the response is the
    /// same `{user: ...}` envelope, per `OurSession.updateUserModel`'s
    /// `setUser(map['user'])`).
    @discardableResult
    func updateProfile(name: String, fName: String?, lName: String?, dateOfBirth: String, gender: String, image: String?) async throws -> User

    /// `EndPoints.getLanguagesApi` (`/languages`, GET) — the full list the
    /// content-language picker renders, in server (`rank`) order.
    func fetchLanguages() async throws -> [LanguageOption]

    /// `LanguageNotifier.saveLanguages` — persists the ordered pick (index 0
    /// is the primary) and refreshes the cached `User`'s `languages`/
    /// `primaryLanguage`/`status` from the response, mirroring
    /// `OurSession.changeContentLanguages`.
    func saveLanguages(_ languages: [String], primaryLanguage: String?) async throws

    /// `OurSession.fetchUserDetails()`'s network half — re-confirms the
    /// account and refreshes the cached `User`. A 403 first tries the refresh
    /// token once and only logs the session out (and throws) if that is also
    /// refused or the retry is still 403; a 404 logs out straight away. Any
    /// other failure (5xx, network) never signs out and is swallowed by the
    /// caller's own tolerance for it, matching Dart's background-refresh
    /// tolerance (see the implementation's doc comment).
    @discardableResult
    func fetchCurrentUser() async throws -> User

    /// `session.dart`'s `logout()`: a fire-and-forget `/user/logout` call
    /// (errors are tracked, never surfaced) followed by clearing the local
    /// session. Deliberately narrow — the full playback/analytics/Realm/
    /// CarPlay/websocket teardown cascade in Dart's `logout()` belongs to
    /// T26 (Session lifecycle), not here.
    func logout() async
}

extension AuthRepository {
    /// Account setup never sets a photo.
    @discardableResult
    func updateProfile(name: String, fName: String?, lName: String?, dateOfBirth: String, gender: String) async throws -> User {
        try await updateProfile(name: name, fName: fName, lName: lName, dateOfBirth: dateOfBirth, gender: gender, image: nil)
    }
}
