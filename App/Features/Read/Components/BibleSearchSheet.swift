import SwiftUI

/// T55 — ported from `bible_search_panel.dart`: recent list before typing, a
/// debounced `/book/search` result after (verse/chapter match, free-text
/// match, or a whole-book match), each state identical to the Dart panel's
/// own `_buildContent` switch. Bare-content, presented via
/// `.appSheet(isPresented:)` per `BookTableOfContentsSheet.swift`'s
/// convention — `ReaderView` owns the toolbar entry point and presentation
/// (deferred integration, not part of this file).
struct BibleSearchSheet: View {
    let languageName: String
    let onVerseTap: (BibleSearchResult) -> Void
    let onBookTap: (BibleBookRef) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = BibleSearchViewModel()
    @FocusState private var isFieldFocused: Bool

    private var trimmedQuery: String {
        viewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SearchTextField(
                text: Binding(
                    get: { viewModel.queryText },
                    set: { viewModel.queryChanged($0, languageName: languageName) }
                ),
                placeholder: "Search by reference, book, or words",
                onClear: { viewModel.clearButtonTapped() }
            )
            .focused($isFieldFocused)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            Text(viewModel.hasQuery ? "Results" : "Recent")
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .padding(.horizontal, Spacing.md)

            ScrollView {
                content
                    .padding(Spacing.md)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { isFieldFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasQuery {
            recentContent
        } else if viewModel.isLoading {
            loadingSkeleton
        } else if viewModel.hasError {
            messageView(icon: .warning, text: "Search failed, try again.")
        } else {
            responseContent
        }
    }

    @ViewBuilder
    private var recentContent: some View {
        if viewModel.recent.isEmpty {
            messageView(icon: .search, text: "Search by reference, book, or words")
        } else {
            resultsList(viewModel.recent, highlightQuery: "", showsRemove: true)
        }
    }

    @ViewBuilder
    private var responseContent: some View {
        switch viewModel.response {
        case .verse(_, _, let verses):
            if verses.isEmpty {
                emptyResultsMessage
            } else {
                resultsList(verses, highlightQuery: trimmedQuery, showsRemove: false)
            }
        case .content(_, let results):
            if results.isEmpty {
                emptyResultsMessage
            } else {
                resultsList(results, highlightQuery: trimmedQuery, showsRemove: false)
            }
        case .book(let book, let note):
            bookCard(book, note: note)
        case .empty(_):
            emptyResultsMessage
        case nil:
            emptyResultsMessage
        }
    }

    private var emptyResultsMessage: some View {
        messageView(icon: .search, text: "No results found")
    }

    private func messageView(icon: IconToken, text: String) -> some View {
        VStack(spacing: Spacing.sm) {
            theme.icon(icon)
                .font(.system(size: 32))
                .foregroundStyle(theme.color(.textTertiary))
            Text(text)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textSecondary))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private func resultsList(_ results: [BibleSearchResult], highlightQuery: String, showsRemove: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(results, id: \.reference) { result in
                verseCard(result, highlightQuery: highlightQuery, showsRemove: showsRemove)
            }
        }
    }

    /// A plain tap-gesture container, not a `Button`, so the nested "remove
    /// from recent" `Button` gets its own independent tap target — mirrors
    /// Dart's `InkWell` (card) wrapping an `InkResponse` (remove) that
    /// "consumes its own tap so the card doesn't open"; nesting a `Button`
    /// inside another `Button`'s label doesn't route taps that way in
    /// SwiftUI.
    private func verseCard(_ result: BibleSearchResult, highlightQuery: String, showsRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                highlightedText(result.numberedText, query: highlightQuery)
                    .typography(Typography.bodyMedium)
                    .italic()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.xs)
                if showsRemove {
                    Button {
                        viewModel.removeRecent(result)
                    } label: {
                        theme.icon(.close)
                            .foregroundStyle(theme.color(.textTertiary))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(result.dotReference)
                .typography(Typography.bodyMedium)
                .fontWeight(.bold)
                .foregroundStyle(theme.color(.textPrimary))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.color(.surfaceSecondary))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(theme.color(.border))
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.recordTap(result)
            onVerseTap(result)
            dismiss()
        }
    }

    private func bookCard(_ book: BibleBookRef, note: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let note, !note.isEmpty {
                Text(note)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
            }
            Button {
                onBookTap(book)
                dismiss()
            } label: {
                HStack(spacing: Spacing.sm) {
                    theme.icon(.tabRead)
                        .foregroundStyle(theme.color(.textSecondary))
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(book.bookName)
                            .typography(Typography.bodyMedium)
                            .fontWeight(.bold)
                            .foregroundStyle(theme.color(.textPrimary))
                        Text("\(book.chapters) chapters")
                            .typography(Typography.bodySmall)
                            .foregroundStyle(theme.color(.textSecondary))
                    }
                    Spacer()
                    theme.icon(.chevronForward)
                        .foregroundStyle(theme.color(.textTertiary))
                }
                .padding(Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(theme.color(.surfaceSecondary))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(theme.color(.border))
                        }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingSkeleton: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SkeletonBox(height: 12)
                    SkeletonBox(width: 120, height: 12)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(theme.color(.surfaceSecondary))
                }
            }
        }
        .shimmer()
    }

    /// Case-insensitive substring highlight, matched directly on `text`'s
    /// own indices (never a `.lowercased()` copy's indices, which aren't
    /// guaranteed to line up with the original string's) — safer than
    /// Dart's own `toLowerCase()` + shared-index approach, which relies on
    /// Dart strings' UTF-16 code-unit indexing happening to survive
    /// case-folding for the Latin text this app searches.
    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else {
            return Text(text).foregroundColor(theme.color(.textSecondary))
        }
        var result = Text("")
        var cursor = text.startIndex
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            if range.lowerBound > cursor {
                result = result + Text(text[cursor..<range.lowerBound]).foregroundColor(theme.color(.textSecondary))
            }
            result = result + Text(text[range]).foregroundColor(theme.color(.textPrimary)).fontWeight(.bold)
            cursor = range.upperBound
            searchRange = range.upperBound..<text.endIndex
        }
        if cursor < text.endIndex {
            result = result + Text(text[cursor...]).foregroundColor(theme.color(.textSecondary))
        }
        return result
    }
}
