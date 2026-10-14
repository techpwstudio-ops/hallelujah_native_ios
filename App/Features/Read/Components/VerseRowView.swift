import SwiftUI

/// `VerseUnitUI` (`lib/views/read/widgets/verse_unit_ui.dart`) — one verse
/// inside the reader list. Spec: "<n>. <text>" at 18pt Helvetica Neue Light
/// (Flutter: bodyLarge, w300, height 1.5), white — or the saved highlight
/// colour when the verse is highlighted (Flutter tints the *text*, not the
/// background) — with 8pt vertical padding. A saved note renders below as a
/// #1D1D1D 16pt-radius card (3 lines + "Read more") carrying a white "Notes"
/// tag. A verse the reader was sent to (search / verse of the day) gets the
/// dark-gold 30% background, 8pt radius, for 3 seconds (`isFocused`).
///
/// Flutter's per-word `SelectableText` toolbar (Ask Emet / Highlight|Remove /
/// Share / Select All / Notes) becomes the verse's long-press context menu —
/// the same actions in the same order, minus "Select All" (SwiftUI `Text`
/// exposes no custom selection toolbar). Flutter also justifies the text;
/// SwiftUI has no justified alignment, so it stays leading-aligned.
struct VerseRowView: View {
    let verse: BibleVerse
    let highlightColorHex: String?
    let noteContent: String?
    let isFocused: Bool
    let onRequestHighlight: () -> Void
    let onRemoveHighlight: () -> Void
    let onOpenNote: () -> Void
    let onShare: () -> Void
    let onAskEmet: () -> Void

    private static let fontSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(verse.verseNumber). \(verse.text)")
                .font(.custom(Typography.fontFamily, size: Self.fontSize, relativeTo: .body).weight(.light))
                .lineSpacing(Self.fontSize * 0.5)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contextMenu {
                    Button(action: onAskEmet) {
                        Text("Ask Emet")
                    }
                    if highlightColorHex != nil {
                        Button(action: onRemoveHighlight) {
                            Text("Remove")
                        }
                    } else {
                        Button(action: onRequestHighlight) {
                            Text("Highlight")
                        }
                    }
                    Button(action: onShare) {
                        Text("Share")
                    }
                    Button(action: onOpenNote) {
                        Text("Notes")
                    }
                }

            if let noteContent, !noteContent.isEmpty {
                noteCard(noteContent)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? ReadPalette.darkGold.opacity(0.3) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.5), value: isFocused)
    }

    private var textColor: Color {
        if isFocused { return ReadPalette.white }
        if let highlightColorHex, let color = Color(readHex: highlightColorHex) { return color }
        return ReadPalette.white
    }

    private func noteCard(_ content: String) -> some View {
        ZStack(alignment: .topLeading) {
            ExpandableNoteText(text: content)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                        .fill(ReadPalette.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                        .strokeBorder(ReadPalette.fill, lineWidth: 1)
                )
                .padding(.top, 16)

            Text("Notes")
                .readText(Typography.bodySmall, weight: .bold, color: ReadPalette.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ReadPalette.white)
                )
        }
    }
}

private struct NoteHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NoteFullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// `ExpandableText` from the same Flutter file: `maxLines: 3`, a bold
/// "Read more" / "Read less" toggle (4pt above) only when the text overflows.
private struct ExpandableNoteText: View {
    let text: String

    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    @State private var hasOverflowedOnce = false
    private var overflows: Bool { hasOverflowedOnce }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(bodyFont)
                .lineSpacing(16 * 0.5)
                .foregroundStyle(ReadPalette.white)
                .lineLimit(expanded ? nil : 3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: NoteHeightKey.self, value: proxy.size.height)
                    }
                )
                .background(
                    Text(text)
                        .font(bodyFont)
                        .lineSpacing(16 * 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: NoteFullHeightKey.self, value: proxy.size.height)
                            }
                        )
                )

            if overflows {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Read less" : "Read more")
                        .font(bodyFont)
                        .fontWeight(.bold)
                        .foregroundStyle(ReadPalette.white)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .onPreferenceChange(NoteHeightKey.self) { value in
            shownHeight = value
            if !expanded && fullHeight > value + 1 { hasOverflowedOnce = true }
        }
        .onPreferenceChange(NoteFullHeightKey.self) { value in
            fullHeight = value
            if !expanded && value > shownHeight + 1 { hasOverflowedOnce = true }
        }
    }

    /// Flutter: bodyLarge, w300 (the verse `fontStyle`), white.
    private var bodyFont: Font {
        .custom(Typography.fontFamily, size: 16, relativeTo: .body).weight(.light)
    }
}
