import SwiftUI

/// `BibleSearchPanel` (`lib/views/read/widgets/bible_search_panel.dart`): the
/// dropdown under the reader's inline search bar — a #1C1C1C card (12pt
/// radius, #2A2A2A border, 16/4/16/16 margin, at most 80% of the screen)
/// headed "Recent" (no query) or "Results" (titleMedium w600), then recent
/// verses, a shimmer while loading, "Search failed, try again.", verse/content
/// cards with the query highlighted, a book card, or "No results found".
/// (File keeps its original name; the type replaced the old modal sheet.)
struct BibleSearchPanel: View {
    let viewModel: BibleSearchViewModel
    let maxHeight: CGFloat
    let onVerseTap: (BibleSearchResult) -> Void
    let onBookTap: (BibleBookRef) -> Void

    private var query: String { viewModel.queryText }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.hasQuery ? "Results" : "Recent")
                .readText(Typography.titleMedium, weight: .semibold)
                .padding(EdgeInsets(top: Dimens.paddingLarge, leading: Dimens.paddingLarge, bottom: Dimens.paddingSmall, trailing: Dimens.paddingLarge))

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                .fill(ReadPalette.darkSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                .strokeBorder(ReadPalette.lyricsBorder, lineWidth: 1)
        )
        .frame(maxHeight: maxHeight)
        .padding(EdgeInsets(top: Dimens.spacing4, leading: Dimens.screenPadding, bottom: Dimens.screenPadding, trailing: Dimens.screenPadding))
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasQuery {
            if viewModel.recent.isEmpty {
                messageView(icon: "magnifyingglass", text: "Search by reference, book, or words")
            } else {
                verseList(viewModel.recent, highlightQuery: "", showsRemove: true)
            }
        } else if viewModel.isLoading {
            shimmer
        } else if viewModel.hasError {
            messageView(icon: "exclamationmark.circle", text: "Search failed, try again.")
        } else {
            responseContent
        }
    }

    @ViewBuilder
    private var responseContent: some View {
        switch viewModel.response {
        case .verse(_, _, let verses):
            if verses.isEmpty {
                emptyMessage
            } else {
                verseList(verses, highlightQuery: trimmedQuery, showsRemove: false)
            }
        case .content(_, let results):
            if results.isEmpty {
                emptyMessage
            } else {
                verseList(results, highlightQuery: trimmedQuery, showsRemove: false)
            }
        case .book(let book, let note):
            bookContent(book, note: note)
        case .empty(_):
            emptyMessage
        case nil:
            emptyMessage
        }
    }

    private var emptyMessage: some View {
        messageView(icon: "magnifyingglass", text: "No results found")
    }

    private func messageView(icon: String, text: String) -> some View {
        VStack(spacing: Dimens.spacing12) {
            Image(systemName: icon)
                .font(.system(size: Dimens.iconSize + 12))
                .foregroundStyle(ReadPalette.greyMuted)
            Text(text)
                .readText(Typography.bodyMedium, color: ReadPalette.greySubtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.vertical, Dimens.spacing32)
    }

    private func verseList(_ results: [BibleSearchResult], highlightQuery: String, showsRemove: Bool) -> some View {
        PanelScroll(maxHeight: maxHeight) {
            LazyVStack(alignment: .leading, spacing: Dimens.spacing12) {
                ForEach(results, id: \.reference) { result in
                    verseCard(result, highlightQuery: highlightQuery, showsRemove: showsRemove)
                }
            }
            .padding(EdgeInsets(top: Dimens.spacing4, leading: Dimens.paddingLarge, bottom: Dimens.paddingLarge, trailing: Dimens.paddingLarge))
        }
    }

    private func verseCard(_ result: BibleSearchResult, highlightQuery: String, showsRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: Dimens.spacing12) {
            HStack(alignment: .top, spacing: Dimens.spacing4) {
                Text("\u{201C}")
                    .font(.custom(Typography.fontFamily, size: 24, relativeTo: .body).weight(.bold).italic())
                    .foregroundStyle(ReadPalette.white70)
                    .frame(height: 24, alignment: .top)
                Text(highlightedString(result.numberedText, query: highlightQuery))
                    .lineSpacing(14 * 0.4)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Dimens.spacing4)
                if showsRemove {
                    Button {
                        viewModel.removeRecent(result)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: Dimens.iconSizeSmall - 4, weight: .semibold))
                            .foregroundStyle(ReadPalette.white60)
                            .frame(width: Dimens.iconSizeSmall, height: Dimens.iconSizeSmall)
                            .padding(.leading, Dimens.spacing4)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(result.dotReference)
                .readText(Typography.bodyMedium, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Dimens.paddingLarge)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .fill(ReadPalette.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(ReadPalette.lyricsBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onVerseTap(result)
        }
    }

    private func bookContent(_ book: BibleBookRef, note: String?) -> some View {
        PanelScroll(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 0) {
                if let note, !note.isEmpty {
                    Text(note)
                        .readText(Typography.bodySmall, color: ReadPalette.greySubtle)
                        .padding(.bottom, Dimens.spacing12)
                }
                Button {
                    onBookTap(book)
                } label: {
                    HStack(spacing: Dimens.spacing12) {
                        Image(systemName: "book")
                            .font(.system(size: Dimens.iconSize))
                            .foregroundStyle(ReadPalette.white70)
                        VStack(alignment: .leading, spacing: Dimens.spacing4) {
                            Text(book.bookName)
                                .readText(Typography.bodyMedium, weight: .bold)
                            Text("\(book.chapters) chapters")
                                .readText(Typography.bodySmall, color: ReadPalette.greySubtle)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: Dimens.iconSize - 8))
                            .foregroundStyle(ReadPalette.white60)
                    }
                    .padding(Dimens.paddingLarge)
                    .background(
                        RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                            .fill(ReadPalette.black)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(ReadPalette.lyricsBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: Dimens.spacing4, leading: Dimens.paddingLarge, bottom: Dimens.paddingLarge, trailing: Dimens.paddingLarge))
        }
    }

    private var shimmer: some View {
        VStack(spacing: Dimens.spacing12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 0) {
                    PulseBar(width: nil, height: 12)
                    Spacer().frame(height: Dimens.spacing8)
                    PulseBar(width: nil, height: 12)
                    Spacer().frame(height: Dimens.spacing16)
                    PulseBar(width: 120, height: 12)
                }
                .padding(Dimens.paddingLarge)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .fill(ReadPalette.black)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(ReadPalette.lyricsBorder, lineWidth: 1)
                )
            }
        }
        .padding(EdgeInsets(top: Dimens.spacing4, leading: Dimens.paddingLarge, bottom: Dimens.paddingLarge, trailing: Dimens.paddingLarge))
    }

    /// Verse text (numbered): bodyMedium italic white 70%, matches of the
    /// query white w700 on the logo colour at 30%.
    private func highlightedString(_ text: String, query: String) -> AttributedString {
        let baseFont = Font.custom(Typography.fontFamily, size: 14, relativeTo: .body).italic()
        let boldFont = Font.custom(Typography.fontFamily, size: 14, relativeTo: .body).weight(.bold).italic()

        func piece(_ value: String, highlighted: Bool) -> AttributedString {
            var attributed = AttributedString(value)
            if highlighted {
                attributed.font = boldFont
                attributed.foregroundColor = ReadPalette.white
                attributed.backgroundColor = ReadPalette.logo.opacity(0.3)
            } else {
                attributed.font = baseFont
                attributed.foregroundColor = ReadPalette.white70
            }
            return attributed
        }

        guard !query.isEmpty else { return piece(text, highlighted: false) }

        var result = AttributedString()
        var cursor = text.startIndex
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            if range.lowerBound > cursor {
                result.append(piece(String(text[cursor..<range.lowerBound]), highlighted: false))
            }
            result.append(piece(String(text[range]), highlighted: true))
            cursor = range.upperBound
            searchRange = range.upperBound..<text.endIndex
        }
        if cursor < text.endIndex {
            result.append(piece(String(text[cursor...]), highlighted: false))
        }
        return result
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A scroll view that shrinks to its content (Flutter's `shrinkWrap` list
/// inside a `Flexible`), up to `maxHeight`.
private struct PanelScroll<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content

    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
        .onPreferenceChange(PanelHeightKey.self) { value in
            contentHeight = value
        }
    }
}

/// Shimmer stand-in for `Shimmer.fromColors(base #1D1D1D, highlight #282828)`:
/// a bar that pulses between the two colours.
private struct PulseBar: View {
    let width: CGFloat?
    let height: CGFloat

    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .continuous)
            .fill(pulsing ? ReadPalette.darkFill : ReadPalette.fill)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
