import SwiftUI

/// Lays words out left to right and wraps them at the proposed width. Each word
/// is its own subview, so each can be its own tap target (Phase 2, decision D-I1).
struct WordFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0, cursorX + size.width > maxWidth {
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }
            cursorX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, cursorX - horizontalSpacing)
        }
        return CGSize(width: proposal.width ?? widest, height: cursorY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX, cursorX + size.width > bounds.maxX {
                cursorX = bounds.minX
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), anchor: .topLeading, proposal: .unspecified)
            cursorX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The colour of one transcript word. Spoken words are white, the word being
/// spoken uses the brand accent, and upcoming words are white at 38%, the same
/// as `LyricsLineItem` (I7).
enum TranscriptWordColor {
    static func color(spoken: Bool, active: Bool) -> Color {
        if active { return ColorToken.brandPrimary.color }
        return spoken ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.38)
    }
}

/// One paragraph of the transcript. `Equatable` so that a word change re-renders
/// only the paragraph it lands in. `state` carries the active word only for the
/// active paragraph (plan §5). The closure is left out of `==`.
struct TranscriptParagraphView: View, Equatable {
    enum State: Equatable {
        case spoken
        case upcoming
        case active(wordOffset: Int)
    }

    let words: [String]
    let firstWordIndex: Int
    let state: State
    let onWordTap: (Int) -> Void

    static func == (lhs: TranscriptParagraphView, rhs: TranscriptParagraphView) -> Bool {
        lhs.words == rhs.words && lhs.firstWordIndex == rhs.firstWordIndex && lhs.state == rhs.state
    }

    var body: some View {
        WordFlowLayout {
            ForEach(words.indices, id: \.self) { offset in
                Text(words[offset])
                    .typography(PlayerStyle.lyricsLine)
                    .foregroundStyle(color(forWordOffset: offset))
                    .contentShape(Rectangle())
                    .onTapGesture { onWordTap(firstWordIndex + offset) }
            }
        }
    }

    private func color(forWordOffset offset: Int) -> Color {
        switch state {
        case .spoken:
            return TranscriptWordColor.color(spoken: true, active: false)
        case .upcoming:
            return TranscriptWordColor.color(spoken: false, active: false)
        case let .active(activeOffset):
            return TranscriptWordColor.color(spoken: offset < activeOffset, active: offset == activeOffset)
        }
    }
}
