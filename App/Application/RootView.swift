import SwiftUI
import UIKit

/// Branches between the splash and whatever it resolves to
/// (`FlashScreen`'s `NavigationService.offAll(destination)` —
/// `lib/views/launch/flash.dart`). `.app` lands on the real `AppShellView`
/// (T16). `.authentication` lands on `AuthenticationView` (T21-23) — success
/// there calls back into `SplashViewModel.handleAuthenticationSuccess(
/// requiresAccountSetup:)`, which flips `destination` to `.accountSetup` or
/// `.app` and re-renders this `switch`. `.accountSetup` (T24) lands on
/// `AccountSetupView`; finishing it calls `handleAccountSetupComplete()`.
///
/// None of these three ever sit inside a shared `NavigationStack` here, same
/// as Dart reaching each of their routes via `NavigationService.offAll(...)`
/// (a full stack replacement, not a push) — see `AccountSetupView`'s own doc
/// comment for why that also means it needs no back-navigation chrome.
///
/// T26 — also watches `SignOutSignal` so a session that ends AFTER this
/// already resolved (an explicit logout, once T70 adds a way to trigger one,
/// or a silent refresh-token failure — already live via `HTTPClient`'s 401
/// handling) falls back to `.authentication` too, not just the one-shot
/// resolution `SplashViewModel.start()` does at launch.
struct RootView: View {
    @State private var launchViewModel = SplashViewModel()
    @State private var signOutSignal: SignOutSignal = DependencyContainer.current.resolve()

    var body: some View {
        Group {
            switch launchViewModel.destination {
            case nil:
                SplashView(viewModel: launchViewModel)
            case .authentication:
                AuthenticationView(onAuthenticated: { requiresAccountSetup in
                    Self.dismissKeyboard()
                    launchViewModel.handleAuthenticationSuccess(requiresAccountSetup: requiresAccountSetup)
                })
            case .accountSetup:
                AccountSetupView(onComplete: {
                    Self.dismissKeyboard()
                    launchViewModel.handleAccountSetupComplete()
                })
            case .app:
                AppShellView()
            }
        }
        .onChange(of: signOutSignal.generation) { _, _ in
            Self.dismissKeyboard()
            launchViewModel.handleSignedOut()
        }
    }

    /// Resigns whatever text field still holds first responder before the
    /// `switch` above swaps the whole tree. Tearing out a focused field (the
    /// OTP screen's hidden auto-focused number field) doesn't reliably take
    /// the keyboard with it, so without this the number pad stayed up over
    /// Home after login.
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    RootView()
}
