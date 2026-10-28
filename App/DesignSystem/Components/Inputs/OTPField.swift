import SwiftUI

/// Ported from `defaultPinTheme`/`Pinput` usage in
/// `lib/features/authentication/email_auth/presentation/otp_screen.dart`
/// (identical box theme is reused by the phone-auth OTP screen). SwiftUI has
/// no per-character input control, so this uses the standard native
/// recipe: one invisible `TextField` drives the digits, `length` boxes render
/// them — the boxes are pure display, all real editing/selection/paste/
/// autofill behavior comes from the hidden field for free (including
/// `.textContentType(.oneTimeCode)`'s SMS autofill, which Dart gets from
/// `otp_sms_retriever.dart`'s own platform channel instead).
///
/// Box size (56×56) and corner radius (`Radius.md`, from `values.dart`'s
/// `cornerRadius = 8.0`) match Dart's `defaultPinTheme` exactly, since this
/// component will sit inside T21/T22's pixel-parity auth screens (D10). Fill
/// uses `surfaceInput` (see `AppTextField.swift`'s note — this box IS a text
/// entry surface, just styled as boxes, so the same token applies). The
/// error border maps 1:1 to Dart's `Colors.red` via `statusError`. The
/// focused border does NOT map to a brand color: Dart's `focusedPinTheme`
/// uses a one-off literal blue (`Color.fromRGBO(114, 178, 238, 1)`) distinct
/// from every other focus treatment in the app (`AppTextField`'s focused
/// border is a plain translucent white). The auth screens pass that literal
/// as `focusedBorderColor` (`AuthColors.focusedBorder`); `statusInfo` is only
/// the fallback for any caller that doesn't.
struct OTPField: View {
    @Binding var code: String
    var length: Int = 6
    var hasError: Bool = false
    var enabled: Bool = true
    var focusedBorderColor: Color? = nil
    var onCompleted: ((String) -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool

    private static let boxSize: CGFloat = 56

    var body: some View {
        ZStack {
            HStack(spacing: Spacing.sm) {
                ForEach(0..<length, id: \.self) { index in
                    box(at: index)
                }
            }

            TextField("", text: $code)
                // ASCII pad: `.numberPad` types Devanagari/Arabic-Indic digits
                // when the app or device language uses them.
                .keyboardType(.asciiCapableNumberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .focused($isFocused)
                .disabled(!enabled)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    // Also normalises pasted/autofilled non-ASCII digits (`१०६२९`) to `10629`.
                    let filtered = String(newValue.asciiDigits.prefix(length))
                    if filtered != newValue {
                        code = filtered
                    }
                    if filtered.count == length {
                        onCompleted?(filtered)
                    }
                }
        }
        .contentShape(Rectangle())
        // Pinput `autofocus: true` on the OTP screens.
        .onAppear { isFocused = true }
        .onTapGesture { isFocused = true }
        .animation(MotionCurve.fast, value: code.count)
        .animation(MotionCurve.fast, value: hasError)
    }

    private func box(at index: Int) -> some View {
        let characters = Array(code)
        let digit = index < characters.count ? String(characters[index]) : nil
        let isCurrent = enabled && isFocused && index == characters.count

        return RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(theme.color(.surfaceInput))
            .frame(width: Self.boxSize, height: Self.boxSize)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(borderColor(isCurrent: isCurrent), lineWidth: borderWidth(isCurrent: isCurrent))
            }
            .overlay {
                if let digit {
                    Text(digit)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            }
            .opacity(enabled ? 1 : 0.5)
    }

    private func borderColor(isCurrent: Bool) -> Color {
        if hasError { return theme.color(.statusError) }
        if isCurrent { return focusedBorderColor ?? theme.color(.statusInfo) }
        return .clear
    }

    private func borderWidth(isCurrent: Bool) -> CGFloat {
        hasError ? 2 : (isCurrent ? 1 : 0)
    }
}
