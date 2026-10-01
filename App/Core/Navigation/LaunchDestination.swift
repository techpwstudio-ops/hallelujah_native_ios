/// Where the splash hands off to once bootstrap resolves — mirrors
/// `FlashScreen._resolveDestination()`'s route choice
/// (`lib/views/launch/flash.dart`), gated on `session.user!.isAccountSet()`
/// (`User.isAccountSet`/`needsAccountSetup` here).
enum LaunchDestination: Sendable, Equatable {
    case authentication
    case accountSetup
    case app
}
