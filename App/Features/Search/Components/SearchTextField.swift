import SwiftUI

/// The search bar's own field chrome — leading magnifying glass, trailing
/// clear button. `AppTextField` (`Core components`) has neither slot (its
/// only trailing affordance is the secure-entry eye toggle), so this is a
/// dedicated sibling rather than a stretched `AppTextField` variant.
///
/// A plain `@Binding<String>`, same shape as `AppTextField` itself: the
/// debounce/commit logic lives in `SearchViewModel`, reached through
/// whatever the caller wires the binding's setter to, not in here.
struct SearchTextField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onClear: () -> Void = {}

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            theme.icon(.search)
                .foregroundStyle(theme.color(.textTertiary))

            TextField(placeholder, text: $text)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button(action: onClear) {
                    theme.icon(.close)
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
        .animation(MotionCurve.fast, value: text.isEmpty)
    }
}
