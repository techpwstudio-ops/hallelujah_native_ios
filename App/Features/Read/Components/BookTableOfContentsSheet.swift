import SwiftUI

/// T54 (Bible reader) -- ported from `table_of_content_sheet.dart`'s book
/// list: every `BibleBook` the reader can jump to, each row showing its
/// canonical English name plus a chapter-count badge (mirrors Dart's own
/// per-row chapter-count pill). Presented from `ReaderView` via
/// `.appSheet(isPresented:)`, so -- same convention as
/// `CountryPickerView.swift` -- this is bare content with no background or
/// drag handle of its own; `AppSheetContainer` supplies both.
struct BookTableOfContentsSheet: View {
    let books: [BibleBook]
    let onSelect: (BibleBook) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(books) { book in
            row(for: book)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func row(for book: BibleBook) -> some View {
        Button {
            onSelect(book)
            dismiss()
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(book.name)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer()
                chapterBadge(book.chapters)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func chapterBadge(_ chapters: Int) -> some View {
        Text("\(chapters) chapters")
            .typography(Typography.labelSmall)
            .foregroundStyle(theme.color(.textSecondary))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background {
                Capsule(style: .continuous)
                    .fill(theme.color(.surfaceSecondary))
            }
    }
}
