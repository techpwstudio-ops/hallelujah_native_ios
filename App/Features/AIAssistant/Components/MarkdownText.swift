import SwiftUI

/// T58 — a lightweight, dependency-free Markdown renderer (no SPM package
/// exists in this project, and this task must not add one). Parses
/// block-level structure line by line — paragraphs, level 1-3 headers,
/// fenced code blocks, blockquotes, bullet list items, horizontal rules —
/// then does a simple regex pass per text run for inline bold/italic/code
/// spans. Not a spec-compliant CommonMark parser — just correct enough for
/// typical AI chat prose, per this task's own scope note.
struct MarkdownText: View {
    let markdown: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)

        case .header(let level, let text):
            inlineText(text)
                .typography(headerTypography(level))
                .foregroundStyle(theme.color(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let code):
            Text(code)
                // No `TypographyToken` in the type scale specifies a
                // monospaced design; same "raw system API, no token fits"
                // fallback this file's own `Image(systemName:)`-style
                // precedent elsewhere in the codebase uses.
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.color(.textPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(theme.color(.surfaceSecondary))
                }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: Spacing.sm) {
                Rectangle()
                    .fill(theme.color(.border))
                    .frame(width: 3)
                inlineText(text)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .listItem(let text):
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("•")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
                inlineText(text)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .horizontalRule:
            Rectangle()
                .fill(theme.color(.separator))
                .frame(height: 1)
                .padding(.vertical, Spacing.xs)
        }
    }

    private func headerTypography(_ level: Int) -> TypographyToken {
        switch level {
        case 1: Typography.titleLarge
        case 2: Typography.titleMedium
        default: Typography.titleSmall
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
        guard (1...3).contains(level) else { return nil }
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
            segment = Text(span.text).italic()
        case .code:
            segment = Text(span.text).font(.system(.footnote, design: .monospaced))
        }
        return partial + segment
    }
}
