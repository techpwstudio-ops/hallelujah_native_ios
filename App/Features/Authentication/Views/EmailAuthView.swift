import SwiftUI

/// Ported from `EmailAuthScreen`
/// (`lib/features/authentication/email_auth/presentation/email_auth_screen.dart`).
/// Embedded inside `AuthenticationView`, not its own screen — same as Dart,
/// where it's a `Column` dropped into `AuthenticationPage`'s form area.
///
/// The email field itself is a hand-styled `TextField`, not the DesignSystem's
/// `AppTextField` (`DesignSystem/Components/Inputs`) despite Dart using its
/// OWN generic `AppTextField` widget here — checked `lib/widgets/
/// app_text_field.dart` directly rather than assuming: its `fillColor`/
/// `_focusedBorder`/`hintStyle` are the same fixed `fillColor`/`Colors.white24`/
/// `ColorTheme.hintColor` literals `AuthColors` already carries for T21, NOT
/// the theme-adaptive tokens the native `AppTextField.swift` renders with (see
/// that file's own doc comment, which flags this exact gap) — so matching
/// Dart's actual on-screen result under D10 means a fixed-literal field here
/// too, same reasoning as `PhoneAuthView`'s hand-styled phone pill.
struct EmailAuthView: View {
    let viewModel: EmailAuthViewModel
    /// Fires with the raw typed email right after a send is kicked off —
    /// mirrors Dart navigating to `EmailOtpScreen` synchronously, without
    /// waiting for `_submitEmail`'s network call.
    let onOTPSent: (String) -> Void

    @State private var email = ""

    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Email")
                .typography(Typography.labelLarge)
                .fontWeight(.medium)
                .foregroundStyle(.white)

            Spacer().frame(height: Spacing.sm)

            TextField(
                "",
                text: $email,
                prompt: Text("you@example.com").font(Typography.bodyMedium.font).foregroundStyle(AuthColors.hint)
            )
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .typography(Typography.bodyLarge)
            .foregroundStyle(.white)
            .focused($isFieldFocused)
            .padding(.horizontal, Spacing.md)
            .frame(height: AuthMetrics.textFieldHeight)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(AuthColors.fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(AuthColors.textFieldFocusedBorder, lineWidth: 1)
                    .opacity(isFieldFocused ? 1 : 0)
            }

            Spacer().frame(height: Spacing.xl)

            AppButton(
                label: "Continue",
                action: { submit() },
                isLoading: viewModel.state == .loading
            )
        }
    }

    /// `_submitEmail` — Dart reports an empty field via a toast and returns;
    /// there is no further client-side validation (the server is the source
    /// of truth for whether an address is well-formed).
    private func submit() {
        guard viewModel.state != .loading else { return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toastCenter.show("Enter your email")
            return
        }
        isFieldFocused = false

        Task { await viewModel.sendOTP(rawEmail: trimmed) }
        onOTPSent(trimmed)
    }
}
