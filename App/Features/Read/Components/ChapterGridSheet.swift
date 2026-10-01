import SwiftUI

/// T54 (Bible reader) -- ported from `table_chapter_sheet.dart`'s chapter
/// grid: a fixed 6-column grid of chapter numbers for the current
/// `BibleBook`, with the current chapter highlighted. Bare sheet content
/// per `BookTableOfContentsSheet.swift`'s doc comment -- no chrome of its
/// own, presented via `.appSheet(isPresented:)` from `ReaderView`.
struct ChapterGridSheet: View {
    let book: BibleBook
    let currentChapter: Int
    let onSelect: (Int) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private static let columnCount = 6
    private static let cellSize: CGFloat = 44

    /// Defensive against a book with a non-positive chapter count -- the
    /// contract's own grounding notes `chapters` is nullable server-side
    /// (mapped defensively, dropped via `compactMap` when missing), but
    /// nothing guarantees a decoded value is `>= 1`, and `1...0` traps.
    private var chapterRange: [Int] {
        Array(1...max(book.chapters, 1))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: Self.columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(book.name)
                    .typography(Typography.titleMedium)
                    .foregroundStyle(theme.color(.textPrimary))

                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(chapterRange, id: \.self) { chapter in
                        cell(for: chapter)
                    }
                }
            }
            .padding(Spacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    private func cell(for chapter: Int) -> some View {
        let isCurrent = chapter == currentChapter
        return Button {
            onSelect(chapter)
            dismiss()
        } label: {
            Text("\(chapter)")
                .typography(Typography.bodyMedium)
                .foregroundStyle(isCurrent ? theme.color(.textInverse) : theme.color(.textPrimary))
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(isCurrent ? theme.color(.textPrimary) : theme.color(.surfaceSecondary))
                }
        }
        .buttonStyle(.plain)
        .animation(MotionCurve.fast, value: isCurrent)
    }
}
