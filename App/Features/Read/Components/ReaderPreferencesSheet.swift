import SwiftUI

/// T54 (Bible reader) -- a genuinely new, native-only preferences sheet:
/// font size + theme have no Dart behavior to port (`ReaderPreferences`'s
/// own grounding notes Dart's font size is hardcoded 18.0 with no picker UI
/// anywhere), built to honestly satisfy the roadmap's "font size, themes"
/// wording. Bare sheet content per `BookTableOfContentsSheet.swift`'s doc
/// comment -- no `@Environment(\.dismiss)`: unlike the other three sheets,
/// this one stays open across repeated taps so preferences can be tuned
/// live, and is dismissed the ordinary way (swipe/drag handle).
struct ReaderPreferencesSheet: View {
    let preferences: ReaderPreferences
    let onFontSizeChange: (Double) -> Void
    let onThemeChange: (ReaderTheme) -> Void

    @Environment(\.appTheme) private var theme

    private var themeBinding: Binding<ReaderTheme> {
        Binding(get: { preferences.theme }, set: onThemeChange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Reader Preferences")
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))

            fontSizeControl
            themeControl
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fontSizeControl: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Font Size")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))

            HStack(spacing: Spacing.md) {
                stepButton(systemName: "minus", enabled: preferences.fontSize > ReaderPreferences.fontSizeRange.lowerBound) {
                    onFontSizeChange(preferences.fontSize - ReaderPreferences.fontSizeStep)
                }

                Text("\(Int(preferences.fontSize))pt")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .frame(minWidth: 44)
                    .multilineTextAlignment(.center)

                stepButton(systemName: "plus", enabled: preferences.fontSize < ReaderPreferences.fontSizeRange.upperBound) {
                    onFontSizeChange(preferences.fontSize + ReaderPreferences.fontSizeStep)
                }
            }
        }
    }

    // No IconToken case for bare plus/minus glyphs (checked IconToken.swift
    // first, per the contract's hard rule) -- raw SF Symbols.
    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(theme.color(.textPrimary))
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(theme.color(.surfaceSecondary))
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private var themeControl: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Theme")
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))

            Picker("Theme", selection: themeBinding) {
                ForEach(ReaderTheme.allCases, id: \.self) { readerTheme in
                    Text(readerTheme.rawValue.capitalized).tag(readerTheme)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
