import SwiftUI

/// Ported from `OtpScreen`
/// (`lib/features/authentication/firebase_phone_auth/presentation/otp_screen.dart`).
/// Pushed from `AuthenticationView` via `.navigationDestination(item:)`,
/// mirroring Dart's `NavigationService.to(OtpScreen.routeName, ...)`.
///
/// Reuses `OTPField` (`DesignSystem/Components/Inputs`) for the six digit
/// boxes rather than rebuilding Pinput's box styling here — see that
/// component's own doc comment for why its `surfaceInput`/`statusInfo`/
/// `statusError` token choices were made with this exact screen in mind.
///
/// One deliberate behavior gap from Dart's `PopScope`: the interactive
/// swipe-back gesture isn't specially intercepted (no direct SwiftUI
/// equivalent that's safe to hand-write without a way to see it run) — only
/// the toolbar back button routes through the "are you sure" confirmation,
/// matching `PopScope`'s `onPopInvokedWithResult`. The edit affordance does
/// NOT: Dart's own edit `InkWell` dispatches `EditPhoneAuthEvent` and pops
/// immediately, with no confirmation at all — confirmed by re-reading
/// `otp_screen.dart`'s edit `onTap`, which has no `showConfirmationDialog`
/// call anywhere near it, unlike the `PopScope` callback a few lines away.
struct OTPView: View {
    let viewModel: PhoneAuthViewModel
    /// The raw number as dialled, passed straight through from
    /// `PhoneAuthView` — matches Dart's `OtpScreen(mobile: fullPhone, ...)`
    /// argument, independent of whatever the bloc/view model's own state
    /// happens to be by the time this renders.
    let mobile: String
    let onAuthSuccess: (_ isNewUser: Bool, _ requiresAccountSetup: Bool) -> Void
    let onEditPhoneNumber: () -> Void

    @State private var code = ""
    @State private var countdown = OTPResendCountdown()
    @State private var isBackConfirmationPresented = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private static let otpLength = 6

    var body: some View {
        ZStack {
            AuthColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: Spacing.lg)

                    Text("Verify Your Phone Number")
                        .typography(Typography.headlineLarge)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer().frame(height: Spacing.xs)

                    HStack(spacing: Spacing.sm) {
                        Text("We've sent a 6-digit code to \(maskedMobile)")
                            .typography(Typography.bodyMedium)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button {
                            viewModel.editPhoneNumber()
                            onEditPhoneNumber()
                        } label: {
                            theme.icon(.edit)
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

                    Text("Code expires in 10 minutes")
                        .typography(Typography.bodySmall)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)

                    Spacer().frame(height: Spacing.xl)

                    AppButton(
                        label: "Verify & Continue",
                        action: { Task { await viewModel.verifyOTP(code: code) } },
                        isLoading: viewModel.state == .loading,
                        enabled: code.count == Self.otpLength
                    )

                    Spacer().frame(height: Spacing.md)

                    AppButton.secondary(
                        countdown.canResend ? "Resend code" : "Resend code (after \(countdown.secondsRemaining)s)",
                        enabled: countdown.canResend
                    ) {
                        guard countdown.canResend else { return }
                        Task {
                            await viewModel.sendOTP(rawPhoneNumber: mobile, isResend: true)
                            countdown.start()
                        }
                    }
                }
                .padding(.horizontal, Spacing.md * 2)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    isBackConfirmationPresented = true
                } label: {
                    theme.icon(.back)
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear { countdown.start() }
        .onDisappear { countdown.stop() }
        .onChange(of: viewModel.state) { _, newState in
            if case .authSuccess(let isNewUser, let requiresAccountSetup) = newState {
                onAuthSuccess(isNewUser, requiresAccountSetup)
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

    private var maskedMobile: String { Self.maskPhoneNumber(mobile) }

    /// Ported 1:1 from `maskPhoneNumber` (`otp_screen.dart`). The Dart source
    /// guarantees `localNumber.length >= 6` by the time it computes
    /// `maskedMiddle` (the early `digits.length < 6` return, plus
    /// `countryCodeLength` never exceeding `digits.length - 10`), so its
    /// `'*' * (localNumber.length - 4)` never sees a negative count; `max(0,
    /// ...)` here is just a defensive mirror of that same invariant, not a
    /// behavior change.
    static func maskPhoneNumber(_ phone: String) -> String {
        guard !phone.isEmpty else { return phone }

        let hasPlus = phone.hasPrefix("+")
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 6 else { return phone }

        let countryCodeLength = digits.count > 10 ? digits.count - 10 : 0
        let countryCode = countryCodeLength > 0 ? String(digits.prefix(countryCodeLength)) : ""
        let localNumber = String(digits.dropFirst(countryCodeLength))

        let start = String(localNumber.prefix(2))
        let end = String(localNumber.suffix(2))
        let maskedMiddle = String(repeating: "*", count: max(0, localNumber.count - 4))

        return "\(hasPlus ? "+" : "")\(countryCode)\(start)\(maskedMiddle)\(end)"
    }
}
