import SwiftUI

/// T54 (Bible reader), extended by T55 -- ported from
/// `book_page_language_sheet.dart`'s language list. T55 adds the search
/// field and per-row offline-download button the T54 doc comment originally
/// deferred here; both were confirmed as this file's own scope, not
/// `BibleSearchSheet`'s (that sheet searches verse/book content within the
/// current language, this one searches the language list itself). Bare
/// sheet content per `BookTableOfContentsSheet.swift`'s doc comment.
struct LanguagePickerSheet: View {
    let languages: [BibleLanguage]
    let currentLanguage: String
    let onSelect: (String) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLanguages: [BibleLanguage] {
        guard !searchText.isEmpty else { return languages }
        return languages.filter { $0.language.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            SearchTextField(
                text: $searchText,
                placeholder: "Search languages",
                onClear: { searchText = "" }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            List(filteredLanguages) { language in
                row(for: language)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity)
    }

    /// A plain tap-gesture row, not a `Button`, so the trailing
    /// `BibleOfflineDownloadButton`'s own tap/long-press gestures get their
    /// own independent hit target -- same reasoning as
    /// `BibleSearchSheet.verseCard`: nesting a `Button` (or a gesture-driven
    /// control) inside another `Button`'s label doesn't route taps
    /// independently in SwiftUI, but two nested plain gesture areas do, the
    /// innermost one winning within its own bounds.
    private func row(for language: BibleLanguage) -> some View {
        let isSelected = language.language == currentLanguage
        return HStack(spacing: Spacing.sm) {
            Text(language.language)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
            Spacer()
            if isSelected {
                // No IconToken case for a bare checkmark glyph (checked
                // IconToken.swift first, per the contract's hard rule) --
                // raw SF Symbol, same as the existing selected-state
                // checkmarks in AddSongsToPlaylistRow/LanguageSelectionViews.
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.color(.brandPrimary))
            }
            BibleOfflineDownloadButton(language: language.language, size: 20)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(language.language)
            dismiss()
        }
        .listRowBackground(Color.clear)
        .animation(MotionCurve.fast, value: isSelected)
    }
}
