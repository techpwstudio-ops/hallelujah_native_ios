import SwiftUI

/// Ported from `PhoneAuthScreen`
/// (`lib/features/authentication/firebase_phone_auth/presentation/phone_auth_screen.dart`).
/// Embedded inside `AuthenticationView`, not its own screen — same as Dart,
/// where it's a `Column` dropped into `AuthenticationPage`'s form area, not a
/// route of its own.
///
/// Two things Dart has that this doesn't:
/// - `flutter_libphonenumber`'s E.164 parse/validate. No native
///   phone-number-parsing library is wired up yet, so `isDigitCountPlausible`
///   below is a coarse stand-in (4–15 digits, E.164's own practical range)
///   rather than a real per-country validation — noted here rather than
///   silently invented as if it were the real thing.
/// - `SimNumberPicker` prefill. Android-only in Dart itself
///   (`if (!Platform.isAndroid) return;`), so it has no iOS counterpart to
///   port at all.
struct PhoneAuthView: View {
    let viewModel: PhoneAuthViewModel
    /// Fires with the full E.164 string right after a send is kicked off —
    /// mirrors Dart navigating to `OtpScreen` synchronously, without waiting
    /// for the network call `_submitPhone` just started.
    let onOTPSent: (String) -> Void

    @State private var selectedCountry = Country.country(forISOCode: "IN") ?? Country.all[0]
    @State private var digits = ""
    @State private var isCountryPickerPresented = false
    @State private var autoSubmittedNumber: String?

    @Environment(\.appTheme) private var theme
    @Environment(\.toastCenter) private var toastCenter
    @FocusState private var isFieldFocused: Bool

    /// `_autoSubmitLength` — also the field's hard cap in Dart, regardless of
    /// the selected country's real number length.
    private static let autoSubmitLength = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Phone Number")
                .typography(Typography.labelLarge)
                .fontWeight(.medium)
                .foregroundStyle(theme.color(.textPrimary))

            Spacer().frame(height: Spacing.sm)

            phoneInputRow

            Spacer().frame(height: Spacing.xl - 2)

            AppButton(
                label: "Continue",
                action: { submit() },
                isLoading: viewModel.state == .loading
            )
        }
        .appSheet(isPresented: $isCountryPickerPresented) {
            CountryPickerView { country in
                selectedCountry = country
            }
        }
    }

    private var phoneInputRow: some View {
        HStack(spacing: 0) {
            Button {
                isFieldFocused = false
                isCountryPickerPresented = true
            } label: {
                HStack(spacing: 0) {
                    Text(selectedCountry.dialCodeDisplay)
                        .typography(Typography.titleMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    DropdownTriangle()
                        .fill(.white)
                        .frame(width: 10, height: 5)
                        .padding(.leading, Spacing.xs)
                        .padding(.trailing, Spacing.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: $digits,
                prompt: Text("Enter phone number").font(Typography.bodyMedium.font).foregroundStyle(AuthColors.hint)
            )
            .keyboardType(.asciiCapableNumberPad)
            .textContentType(.telephoneNumber)
            .typography(Typography.bodyLarge)
            .foregroundStyle(.white)
            .focused($isFieldFocused)
            .onChange(of: digits) { _, newValue in
                let filtered = String(newValue.asciiDigits.prefix(Self.autoSubmitLength))
                if filtered != newValue {
                    digits = filtered
                }
                if filtered.count == Self.autoSubmitLength {
                    autoSubmit(filtered)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AuthMetrics.textFieldHeight)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AuthColors.fill)
        }
    }

    private var isDigitCountPlausible: Bool {
        (4...15).contains(digits.count)
    }

    /// `_submitPhone({bool silent = false})` — `silent` is true only for the
    /// auto-submit path, matching `_validatePhoneNumber(showError: !silent)`:
    /// a number that's 10 digits but not yet plausible is still being typed,
    /// so the auto-submit path stays quiet and waits for the Continue tap.
    private func submit(silent: Bool = false) {
        guard viewModel.state != .loading else { return }
        guard isDigitCountPlausible else {
            if !silent { toastCenter.show("Please enter valid mobile number") }
            return
        }
        isFieldFocused = false

        let fullPhone = selectedCountry.dialCodeDisplay + digits
        Task { await viewModel.sendOTP(rawPhoneNumber: fullPhone) }
        onOTPSent(fullPhone)
    }

    /// Fires at most once per number, same guard as Dart's
    /// `_autoSubmittedNumber` check.
    private func autoSubmit(_ number: String) {
        let candidate = selectedCountry.dialCodeDisplay + number
        guard autoSubmittedNumber != candidate else { return }
        autoSubmittedNumber = candidate
        submit(silent: true)
    }
}

/// Flutter's `Icons.arrow_drop_down`: a small solid down-pointing triangle.
/// `chevron.down` at icon size read as a heavy full-size arrow beside the dial code.
private struct DropdownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
