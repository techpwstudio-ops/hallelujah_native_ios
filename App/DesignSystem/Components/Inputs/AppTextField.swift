import SwiftUI
import UIKit

/// Ported from `AppTextField`/`AppTextFormField` (`lib/widgets/app_text_field.dart`):
/// same optional label-above-field layout, same keyboard-dismiss-on-tap-outside
/// behavior (SwiftUI's default focus-follows-tap already gives us this for
/// free — nothing to wire), same three border states (default/focused/error),
/// same obscure-text eye toggle.
///
/// One behavioral simplification, not a visual one: Dart exposes
/// `obscureText`/`onToggleObscure` as caller-controlled props so the toggle
/// button and the obscured state can live in two different widgets
/// (`AppTextField` vs. `AppTextFormField`). Here the reveal toggle is
/// self-contained internal `@State` — same on-screen behavior, one less thing
/// for every call site to wire.
///
/// Fill color is `surfaceInput`, not `surfacePrimary` (which numerically is
/// the closer match to Dart's literal `fillColor`, #1D1D1D — see
/// `OTPField.swift`'s note on the same tradeoff): `surfaceInput` was
/// purpose-built in T02 to visually distinguish editable text fields from
/// static content surfaces, an intentional improvement D10 leaves room for
/// outside the splash/auth screens.
struct AppTextField: View {
    @Binding var text: String
    var label: String? = nil
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var errorMessage: String? = nil
    var enabled: Bool = true

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let label {
                Text(label)
                    .typography(Typography.labelLarge)
                    .foregroundStyle(theme.color(.textPrimary))
            }

            HStack(spacing: Spacing.sm) {
                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .focused($isFocused)
                .disabled(!enabled)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        theme.icon(isRevealed ? .visibilityOff : .visibilityOn)
                            .foregroundStyle(theme.color(.textTertiary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: Spacing.inputHeight)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(theme.color(.surfaceInput))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: hasError ? 2 : 1)
                    .opacity(showsBorder ? 1 : 0)
            }
            .opacity(enabled ? 1 : 0.5)

            if let errorMessage {
                Text(errorMessage)
                    .typography(Typography.labelSmall)
                    .foregroundStyle(theme.color(.statusError))
            }
        }
        .animation(MotionCurve.fast, value: isFocused)
        .animation(MotionCurve.fast, value: hasError)
    }

    private var hasError: Bool { errorMessage != nil }
    private var showsBorder: Bool { isFocused || hasError }

    private var borderColor: Color {
        hasError ? theme.color(.statusError) : theme.color(.border)
    }
}
