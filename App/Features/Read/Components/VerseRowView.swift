import SwiftUI

/// T54 (Bible reader) — one verse inside `ReaderView`'s chapter list. The
/// verse number renders as a small, raised leading label ahead of the
/// verse's own text (a `Text` concatenation, so it wraps inline with the
/// paragraph the way a printed Bible's verse numbers do, rather than a
/// separate fixed-width column), followed by `verse.text` at the caller's
/// current `fontSize`. A saved highlight tints the row's background; a
/// small `note.text` glyph appears when the verse has a saved note.
///
/// `theme` here is `ReaderTheme` (light/sepia/dark) — this feature's own
/// small, native-only reading preference (see `ReaderPreferences`'s doc
/// comment: Dart's `bookBgColor`/`bookTextColor` keys are read but never
/// written anywhere, so there's no real behavior to port) — not the design
/// system's `AppTheme`. The two are deliberately never both in scope here:
/// this view resolves its own foreground/background colors from
/// `ReaderTheme` directly rather than pulling `\.appTheme` from the
/// environment, so there's no name collision between "this verse row's
/// reading theme" and "the app's design-system theme".
struct VerseRowView: View {
    let verse: BibleVerse
    let highlightColorHex: String?
    let hasNote: Bool
    let fontSize: Double
    let theme: ReaderTheme
    let onHighlight: (String) -> Void
    let onRemoveHighlight: () -> Void
    let onOpenNote: () -> Void
    let onShare: () -> Void
    let onAskEmet: () -> Void

    /// A small fixed swatch set, not a full color picker — matches T54's
    /// whole-verse-only highlight scope cut (see
    /// `BibleRepository.syncHighlight`'s doc comment): these four are the
    /// only highlight inputs anywhere in this feature. A small `Identifiable`
    /// struct rather than a tuple array, so `ForEach` below doesn't need an
    /// explicit `id:` key path into a tuple label.
    private struct HighlightSwatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    private static let highlightSwatches: [HighlightSwatch] = [
        HighlightSwatch(name: "Yellow", hex: "#FDE68A"),
        HighlightSwatch(name: "Green", hex: "#BBF7D0"),
        HighlightSwatch(name: "Blue", hex: "#BFDBFE"),
        HighlightSwatch(name: "Pink", hex: "#FBCFE8"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            (verseNumberText + Text(" ") + verseText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if hasNote {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contextMenu {
            ForEach(Self.highlightSwatches) { swatch in
                Button {
                    onHighlight(swatch.hex)
                } label: {
                    Label(swatch.name, systemImage: "circle.fill")
                }
            }
            if highlightColorHex != nil {
                // Reuses the existing `IconToken.trash` glyph ("trash")
                // rather than inventing a new one — checked `IconToken.swift`
                // first, per the contract's hard rule. No `theme.icon()`
                // call here since this file has no `AppTheme` environment
                // value in scope (see the type's own doc comment) — just
                // the token's raw `systemName`.
                Button(role: .destructive, action: onRemoveHighlight) {
                    Label("Remove Highlight", systemImage: IconToken.trash.systemName)
                }
            }
            Button(action: onOpenNote) {
                Label("Note", systemImage: "note.text")
            }
            Button(action: onShare) {
                Label("Share", systemImage: IconToken.share.systemName)
            }
            Button(action: onAskEmet) {
                Label("Ask Emet", systemImage: IconToken.tabAI.systemName)
            }
        }
    }

    private var verseNumberText: Text {
        Text("\(verse.verseNumber)")
            .font(.system(size: max(fontSize - 6, 10), weight: .bold))
            .baselineOffset(fontSize * 0.35)
            .foregroundColor(secondaryTextColor)
    }

    private var verseText: Text {
        Text(verse.text)
            .font(.system(size: fontSize))
            .foregroundColor(textColor)
    }

    private var rowBackground: Color {
        guard let highlightColorHex, let color = Color(readerHex: highlightColorHex) else {
            return backgroundColor
        }
        return color.opacity(0.35)
    }

    // Reasonable, hand-picked colors — a genuinely new native-only feature
    // (see the type's own doc comment), so there's no Dart source to match
    // these against, only a light/sepia/dark reading-surface convention
    // common to other Bible-reader apps.
    private var backgroundColor: Color {
        switch theme {
        case .light: .white
        case .sepia: Color(red: 0.96, green: 0.92, blue: 0.80)
        case .dark: Color(red: 0.11, green: 0.11, blue: 0.12)
        }
    }

    private var textColor: Color {
        switch theme {
        case .light: .black
        case .sepia: Color(red: 0.30, green: 0.20, blue: 0.09)
        case .dark: .white
        }
    }

    private var secondaryTextColor: Color {
        textColor.opacity(0.55)
    }
}

private extension Color {
    /// No hex-to-`Color` helper exists anywhere in `App/DesignSystem`
    /// (grepped for `init(hex` before adding this) — `ColorToken` only
    /// resolves named asset-catalog colors, never an arbitrary wire hex
    /// string, which is exactly what a verse highlight's `colorHex` is.
    /// Local and `private` to this file, and named `readerHex` rather than
    /// a plain `hex` label, so it can never collide with a real
    /// design-system initializer another feature adds later.
    init?(readerHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
