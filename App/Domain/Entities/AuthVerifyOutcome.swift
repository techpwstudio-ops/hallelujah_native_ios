/// `AuthVerifyResult` (`lib/features/authentication/data/auth_otp_service.dart`)
/// — what `/auth/otp/verify` answers with, beyond the session itself (already
/// finalized by the time this is returned).
struct AuthVerifyOutcome: Sendable, Equatable {
    let user: User
    /// True when this call created the account.
    let isNewUser: Bool
    /// Where to land: `true` -> account setup, `false` -> dashboard. Not the
    /// same as `isNewUser` — someone who signed up yesterday and abandoned
    /// setup comes back as `isNewUser: false` with nothing chosen. Mirrors
    /// the account's server-side `status`, so it can't drift the way a
    /// locally-derived guess could.
    let requiresAccountSetup: Bool
}
