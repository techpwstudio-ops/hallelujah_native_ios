import SwiftUI

/// Ported from `EmailOtpScreen`
/// (`lib/features/authentication/email_auth/presentation/otp_screen.dart`).
/// Pushed from `AuthenticationView` via `.navigationDestination(item:)`, same
/// shape as `OTPView` (phone) — see that file's doc comment for the shared
/// `PopScope`/edit-affordance reasoning, which applies here identically:
/// only the toolbar back button confirms, the edit tap fires immediately.
///
/// Two real behavior differences from `OTPView`, both confirmed by reading
/// this screen's Dart source directly rather than assumed from the phone one:
/// - No masking. Dart passes `_email` straight into `sentSixDigitCodeToEmail`
///   with no equivalent of `maskPhoneNumber` — the full address is shown.
/// - An error toast. `EmailOtpScreen`'s `BlocListener` calls
///   `showSnackBarToast(message: state.error)` for `EmailAuthErrorState`, on
///   top of Pinput's own inline `errorText` — `OtpScreen` (phone)'s listener
///   does neither (`_otpController.clearComposing()` only). Reproduced here
///   via `AuthenticationView`'s `.toastOverlay()`, not added to `OTPView`.
///
/// Also unlike `OTPView`: this screen does not receive its own
/// `onAuthSuccess`/`onEditEmail` callbacks in Dart at all — `EmailOtpScreen`
/// only pops (`NavigationService.back()`) on success and on edit, relying on
/// `EmailAuthScreen`'s own `BlocListener`, still mounted underneath on the
/// nav stack, to notice the same bloc's `AuthSuccessState` and call
/// `widget.onSuccess()` separately. That two-listeners-on-one-stack shape is
/// a Flutter Navigator idiom with no clean SwiftUI equivalent, and no
/// user-visible difference results from skipping it — so this takes explicit
/// `onAuthSuccess`/`onEditEmail` closures instead, the same direct-callback
/// shape `OTPView` already uses for phone.
struct EmailOTPView: View {
    let viewModel: EmailAuthViewModel
    /// The raw email as typed, passed straight through from `EmailAuthView`
    /// — matches Dart's `EmailOtpScreen(email: email)` argument.
    let email: String
    let onAuthSuccess: (_ isNewUser: Bool, _ requiresAccountSetup: Bool) -> Void
    let onEditEmail: () -> Void

    @State private var code = ""
    @State private var countdown = OTPResendCountdown()
    @State private var isBackConfirmationPresented = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter

    private static let otpLength = 6

    var body: some View {
        ZStack {
            AuthColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: Spacing.lg)

                    Text("Verify Your Email")
                        .typography(Typography.headlineLarge)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer().frame(height: Spacing.xs)

                    HStack(spacing: Spacing.sm) {
                        Text("We've sent a 6-digit code to \(email)")
                            .typography(Typography.bodyMedium)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button {
                            viewModel.editEmail()
                            onEditEmail()
                        } label: {
                            theme.icon(.edit, size: 20)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer().frame(height: Spacing.lg)

                    Text("Enter OTP")
                        .typography(Typography.labelLarge)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: Spacing.sm)

                    OTPField(
                        code: $code,
                        length: Self.otpLength,
                        hasError: viewModel.state.isError,
                        focusedBorderColor: AuthColors.focusedBorder,
                        onCompleted: { completedCode in
                            Task { await viewModel.verifyOTP(code: completedCode) }
                        }
                    )
                    .onChange(of: code) { _, _ in
                        if viewModel.state.isError {
                            viewModel.clearError()
                        }
                    }

                    if let errorMessage = viewModel.state.errorMessage {
                        Spacer().frame(height: Spacing.xs)
                        Text(errorMessage)
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.statusError))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer().frame(height: Spacing.xl)

                    Text("The code will expire in 10 minutes.")
                        .typography(Typography.bodySmall)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)

                    Spacer().frame(height: Spacing.xl)

                    AppButton(
                        label: "Verify OTP & Continue",
                        action: { Task { await viewModel.verifyOTP(code: code) } },
                        isLoading: viewModel.state == .loading,
                        enabled: code.count == Self.otpLength
                    )

                    Spacer().frame(height: Spacing.md)

                    AppButton.secondary(
                        countdown.canResend ? String(localized: "Resend code") : String(localized: "Resend code (after \(countdown.secondsRemaining)s)"),
                        enabled: countdown.canResend
                    ) {
                        guard countdown.canResend else { return }
                        Task {
                            await viewModel.sendOTP(rawEmail: email, isResend: true)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md * 2)
                // Native-only tablet/Mac adaptation (no Flutter counterpart):
                // the phone form, centred in a form-width column.
                .readableContentWidth(AdaptiveLayout.formWidth)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            AppBackToolbarItem { isBackConfirmationPresented = true }
        }
        .onAppear { countdown.start() }
        .onDisappear { countdown.stop() }
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .authSuccess(let isNewUser, let requiresAccountSetup):
                onAuthSuccess(isNewUser, requiresAccountSetup)
            case .error(let message, _):
                toastCenter.show(message)
            default:
                break
            }
        }
        .confirmationDialog(
            "Are you sure to go back?",
            isPresented: $isBackConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Yes", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
