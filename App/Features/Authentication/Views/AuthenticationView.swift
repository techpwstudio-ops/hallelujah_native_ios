import SwiftUI

/// Ported from `AuthenticationPage` (`lib/views/auth/authentication_page.dart`)
/// — the single entry point for an unauthenticated user, hosting phone (T21),
/// email (T22), and Google/Apple (T23) sign-in behind one shared brand
/// header, toggle, and terms footer. There is no password anywhere in this
/// flow: sign-in and sign-up are the same action, and the server creates the
/// account at verify time if there is none (T20's `AuthRepository.verifyOTP`,
/// T23's `verifySocialAuth`).
///
/// Owns one `PhoneAuthViewModel`, one `EmailAuthViewModel`, and one
/// `SocialAuthViewModel` for its lifetime — mirrors Dart threading the same
/// `PhoneAuthBloc`/`EmailAuthBloc`/(module-level `AuthBloc`) from their
/// respective screens into pushed destinations via navigation arguments,
/// just as `@State` instances shared with a pushed destination instead. Each
/// OTP channel gets its own `.navigationDestination(item:)`
/// (`OTPView`/`EmailOTPView`) rather than a combined enum, since Dart itself
/// treats them as two independent named routes; social sign-in has no OTP
/// step and so no destination of its own — it resolves in place via
/// `.onChange(of: socialAuthViewModel.state)` below.
///
/// `.toastOverlay()` is applied here, not at the app root: this is the one
/// place that currently needs `showSnackBarToast`-equivalent validation
/// feedback (empty phone/email on submit, OTP errors on the email channel —
/// see `EmailOTPView`'s doc comment for why only that channel shows one —
/// and social sign-in errors, which Dart always toasts). Extending it
/// app-wide is a separate, broader concern for whenever another screen needs
/// it.
struct AuthenticationView: View {
    /// Called once verify succeeds — `RootView`/`SplashViewModel` swap to
    /// `.accountSetup` or `.app` from here. `isNewUser` isn't threaded
    /// through: nothing downstream of this screen branches on it.
    ///
    /// `_navigateToNextScreen` (`authentication_page.dart`) actually
    /// re-reads `OurSession.instance.user?.isAccountSet()` at navigation
    /// time rather than using the verify response's own `requiresAccountSetup`
    /// field — both `user` and that field come from the same response for the
    /// same account, so they can't disagree in practice; reusing the flag
    /// already threaded up from `AuthOTPVerifyResponse`/`SocialAuthViewModel`
    /// avoids giving this view its own `CurrentUserStore` dependency just to
    /// recompute the same answer a second way.
    let onAuthenticated: (_ requiresAccountSetup: Bool) -> Void

    @State private var phoneAuthViewModel = PhoneAuthViewModel()
    @State private var emailAuthViewModel = EmailAuthViewModel()
    @State private var socialAuthViewModel = SocialAuthViewModel()
    @State private var isEmailMode = false
    @State private var otpContext: OTPContext?
    @State private var emailOTPContext: EmailOTPContext?
    /// `KeyboardCubit` — the terms line drops out while the keyboard is up.
    @State private var isKeyboardOpen = false

    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    private struct OTPContext: Identifiable, Hashable {
        let id = UUID()
        let mobile: String
    }

    private struct EmailOTPContext: Identifiable, Hashable {
        let id = UUID()
        let email: String
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        brandHeader

                        Spacer().frame(height: Spacing.md)

                        Text(isEmailMode ? LocalizedStringKey("Continue with Email") : LocalizedStringKey("Continue with Mobile"))
                            .typography(Typography.bodyMedium)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Spacer().frame(height: Spacing.lg)

                        if isEmailMode {
                            EmailAuthView(viewModel: emailAuthViewModel) { email in
                                emailOTPContext = EmailOTPContext(email: email)
                            }
                        } else {
                            PhoneAuthView(viewModel: phoneAuthViewModel) { mobile in
                                otpContext = OTPContext(mobile: mobile)
                            }
                        }

                        Spacer().frame(height: Spacing.lg)

                        TextDividerView(text: "Or")

                        SocialSignInButtonsView(
                            isWithEmail: isEmailMode,
                            onToggleMethod: { isEmailMode.toggle() },
                            isLoading: socialAuthViewModel.state == .loading,
                            onGoogleSignIn: { Task { await socialAuthViewModel.signInWithGoogle() } },
                            onAppleSignIn: { Task { await socialAuthViewModel.signInWithApple() } }
                        )
                    }
                    .frame(minHeight: max(0, geometry.size.height - Spacing.md * 2))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AuthColors.background.ignoresSafeArea())
            // Flutter's `Scaffold` has no `AppBar` here; without hiding the
            // stack's bar the root screen gets a blank 44pt gap at the top.
            // Pushed OTP destinations declare their own toolbar.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardOpen {
                    TermsAndPrivacyTextView()
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.md)
                        .background(AuthColors.background)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardOpen = false
            }
            .navigationDestination(item: $otpContext) { context in
                OTPView(
                    viewModel: phoneAuthViewModel,
                    mobile: context.mobile,
                    onAuthSuccess: { _, requiresAccountSetup in
                        // `performUpdateAuth` toasts 'Authenticated' for both OTP channels.
                        ToastCenter.shared.show("Authenticated")
                        onAuthenticated(requiresAccountSetup)
                    },
                    onEditPhoneNumber: { otpContext = nil }
                )
            }
            .navigationDestination(item: $emailOTPContext) { context in
                EmailOTPView(
                    viewModel: emailAuthViewModel,
                    email: context.email,
                    onAuthSuccess: { _, requiresAccountSetup in
                        // `performUpdateAuth` toasts 'Authenticated' for both OTP channels.
                        ToastCenter.shared.show("Authenticated")
                        onAuthenticated(requiresAccountSetup)
                    },
                    onEditEmail: { emailOTPContext = nil }
                )
            }
            // `googleSignIn`/`loginWithApple`'s `.then((success) { if
            // (success) onSuccess(); })` — social sign-in has no OTP step to
            // navigate through, so success/error are handled in place rather
            // than via a pushed destination.
            .onChange(of: socialAuthViewModel.state) { _, newValue in
                switch newValue {
                case let .success(_, requiresAccountSetup):
                    onAuthenticated(requiresAccountSetup)
                case let .error(message):
                    toastCenter.show(message)
                case .idle, .loading:
                    break
                }
            }
        }
        .toastOverlay()
    }

    private var brandHeader: some View {
        VStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            Spacer().frame(height: Spacing.sm)

            // Dart renders this with Google Fonts "Russo One" (needs the font
            // bundled; until then this falls back to the app font).
            Text("HALLELUJAH")
                .typography(Typography.titleLarge)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Spacer().frame(height: Spacing.md)

            // Dart: Google Fonts "Poppins" w400, same fallback as above.
            Text("MUSIC, PODCAST AND THE WORD")
                .typography(Typography.titleMedium)
                .fontWeight(.regular)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    AuthenticationView(onAuthenticated: { _ in })
}
