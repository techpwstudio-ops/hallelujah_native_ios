import SwiftUI

/// Dependency-free Markdown renderer for assistant replies. Styled to match the
/// `MarkdownStyleSheet` in Flutter's `AiMessageBubble`
/// (`lib/views/ai/widgets/ai_message_bubble.dart`): white 14pt paragraphs at
/// 1.55 line height, bold white strong, italic white70 emphasis, h1/h2/h3
/// 20 bold / 24 bold / 16 w600, amber monospace inline code, `darkFillColor`
/// code blocks, gold-barred blockquotes, 24pt list gutters, white24 rules.
struct MarkdownText: View {
    let markdown: String

    /// `height: 1.55` at 14pt, minus the face's natural ~1.15 line box.
    private static let paragraphLineSpacing: CGFloat = 14 * (1.55 - 1.15)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
                .font(AIColors.font(14))
                .foregroundStyle(Color.white)
                .lineSpacing(Self.paragraphLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

        case .header(let level, let text):
            inlineText(text)
                .font(headerFont(level))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AIColors.amber200)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .fill(AIColors.darkFill)
                }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(AIColors.gold)
                    .frame(width: 3)
                inlineText(text)
                    .font(AIColors.font(14))
                    .italic()
                    .foregroundStyle(AIColors.white70)
                    .lineSpacing(14 * (1.5 - 1.15))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }

        case .listItem(let text):
            listRow(marker: "\u{2022}", text: text)

        case .orderedItem(let number, let text):
            listRow(marker: "\(number).", text: text)

        case .horizontalRule:
            Rectangle()
                .fill(AIColors.white24)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(marker)
                .font(AIColors.font(14))
                .foregroundStyle(Color.white)
                .frame(width: 19, alignment: .trailing)
                .padding(.trailing, 5)
            inlineText(text)
                .font(AIColors.font(14))
                .foregroundStyle(Color.white)
                .lineSpacing(Self.paragraphLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: AIColors.font(20, .bold)
        case 2: AIColors.font(24, .bold)
        default: AIColors.font(16, .semibold)
        }
    }
}

// MARK: - Block model / parser

private enum MarkdownBlock {
    case paragraph(String)
    case header(level: Int, text: String)
    case codeBlock(String)
    case blockquote(String)
    case listItem(String)
    case orderedItem(number: Int, text: String)
    case horizontalRule
}

private enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String]?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            if codeLines != nil {
                if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.codeBlock((codeLines ?? []).joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines?.append(rawLine)
                }
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                codeLines = []
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.horizontalRule)
                continue
            }

            if let level = headerLevel(trimmed) {
                flushParagraph()
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                blocks.append(.header(level: level, text: text))
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.blockquote(String(trimmed.dropFirst(2))))
                continue
            }
            if trimmed == ">" {
                flushParagraph()
                blocks.append(.blockquote(""))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushParagraph()
                blocks.append(.listItem(String(trimmed.dropFirst(2))))
                continue
            }

            if let (number, rest) = orderedListItem(trimmed) {
                flushParagraph()
                blocks.append(.orderedItem(number: number, text: rest))
                continue
            }

            paragraphLines.append(trimmed)
        }

        // An unterminated fence at end-of-string still shows what's there so
        // far rather than swallowing it — relevant for a live-streaming
        // partial buffer mid-delta re-rendering through this same parser.
        if let codeLines, !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
        }
        flushParagraph()

        return blocks
    }

    /// `1. text` / `12) text`.
    private static func orderedListItem(_ trimmed: String) -> (Int, String)? {
        var digits = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber, digits.count < 9 {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty, let number = Int(digits), index < trimmed.endIndex else { return nil }
        let marker = trimmed[index]
        guard marker == "." || marker == ")" else { return nil }
        let afterMarker = trimmed.index(after: index)
        guard afterMarker < trimmed.endIndex, trimmed[afterMarker] == " " else { return nil }
        let rest = String(trimmed[trimmed.index(after: afterMarker)...]).trimmingCharacters(in: .whitespaces)
        return (number, rest)
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let significant = trimmed.filter { !$0.isWhitespace }
        guard significant.count >= 3 else { return false }
        let uniqueChars = Set(significant)
        guard uniqueChars.count == 1, let marker = uniqueChars.first else { return false }
        return marker == "-" || marker == "*" || marker == "_"
    }

    private static func headerLevel(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for character in trimmed {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return level
    }
}

// MARK: - Inline spans (bold / italic / code)

private enum InlineStyle {
    case plain
    case bold
    case italic
    case code
}

private struct InlineSpan {
    let text: String
    let style: InlineStyle
}

/// Matched in priority order — the code-span alternative first, so a
/// `**`/`*`/`_` inside a `` `code` `` span is never mistaken for an emphasis
/// marker. Groups: 1 = code, 2/3 = bold (`**`/`__`), 4/5 = italic (`*`/`_`).
private let inlinePattern: NSRegularExpression? = try? NSRegularExpression(
    pattern: "`([^`]+)`|\\*\\*([^*]+)\\*\\*|__([^_]+)__|\\*([^*]+)\\*|_([^_]+)_"
)

private func parseInlineSpans(_ raw: String) -> [InlineSpan] {
    guard let inlinePattern else { return [InlineSpan(text: raw, style: .plain)] }

    let nsText = raw as NSString
    var spans: [InlineSpan] = []
    var lastEnd = 0

    let matches = inlinePattern.matches(in: raw, range: NSRange(location: 0, length: nsText.length))
    for match in matches {
        if match.range.location > lastEnd {
            let plainRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            spans.append(InlineSpan(text: nsText.substring(with: plainRange), style: .plain))
        }

        if match.range(at: 1).location != NSNotFound {
            spans.append(InlineSpan(text: nsText.substring(with: match.range(at: 1)), style: .code))
        } else if match.range(at: 2).location != NSNotFound {
            spans.append(InlineSpan(text: nsText.substring(with: match.range(at: 2)), style: .bold))
        } else if match.range(at: 3).location != NSNotFound {
            spans.append(InlineSpan(text: nsText.substring(with: match.range(at: 3)), style: .bold))
        } else if match.range(at: 4).location != NSNotFound {
            spans.append(InlineSpan(text: nsText.substring(with: match.range(at: 4)), style: .italic))
        } else if match.range(at: 5).location != NSNotFound {
            spans.append(InlineSpan(text: nsText.substring(with: match.range(at: 5)), style: .italic))
        }

        lastEnd = match.range.location + match.range.length
    }

    if lastEnd < nsText.length {
        spans.append(InlineSpan(text: nsText.substring(from: lastEnd), style: .plain))
    }

    return spans.isEmpty ? [InlineSpan(text: raw, style: .plain)] : spans
}

private func inlineText(_ raw: String) -> Text {
    parseInlineSpans(raw).reduce(Text("")) { partial, span in
        let segment: Text
        switch span.style {
        case .plain:
            segment = Text(span.text)
        case .bold:
            segment = Text(span.text).bold()
        case .italic:
            segment = Text(span.text).italic().foregroundStyle(AIColors.white70)
        case .code:
            segment = Text(span.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AIColors.amber200)
        }
        return partial + segment
    }
}
