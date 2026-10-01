import SwiftUI

/// T56 — ports `_VerseOfDayOptionsSheet` (`verse_of_day_options_sheet.dart`):
/// exactly two rows, "Ask Emet" (hidden when `target.isEmpty` — nothing for
/// Emet to explain) and "Hide for Today". Bare sheet content per
/// `LanguagePickerSheet.swift`'s doc comment — `.appSheet` supplies the drag
/// handle and glass chrome, so this file draws neither.
///
/// Parent-owns-secondary-sheet: unlike Dart's own `onTap`, which calls
/// `showAiVerseInsightDialog` directly, this reports `onAskEmet` upward and
/// leaves presenting `AIVerseInsightDialogView` to `VerseOfDayCardView`
/// (matching `ReaderView.swift`'s own top-level ownership of that dialog) —
/// presenting a second `.sheet` from inside a view already inside a `.sheet`
/// doesn't reliably show in SwiftUI, so the parent must own it.
struct VerseOfDayOptionsSheet: View {
    let verse: VerseOfDay
    let onHide: () -> Void
    let onAskEmet: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private var target: VerseInsightTarget { .fromVerseOfDay(verse) }

    var body: some View {
        VStack(spacing: 0) {
            if !target.isEmpty {
                row(icon: .tabAI, title: "Ask Emet") {
                    dismiss()
                    onAskEmet()
                }
            }
            row(icon: .visibilityOff, title: "Hide for Today") {
                onHide()
                dismiss()
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private func row(icon: IconToken, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                theme.icon(icon)
                    .foregroundStyle(theme.color(.textPrimary))
                Text(title)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
