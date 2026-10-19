import SwiftUI
import UIKit

/// Word-level selectable verse text — Flutter's `SelectableText.rich` in
/// `VerseUnitUI`. SwiftUI's `Text` can't expose the selected range or a custom
/// selection menu, so this wraps a non-editable, selectable `UITextView`.
///
/// Each word can carry its own colour (`wordColors`, keyed by `VerseWords`
/// index — Flutter tints the *text* of highlighted words). Long-pressing a
/// word selects it and shows the custom menu: Ask Emet, Highlight / Remove,
/// Share, Select All, Notes — with the word indices the selection touches.
struct SelectableVerseText: UIViewRepresentable {
    struct Actions {
        /// Whether any of the selected words is already highlighted
        /// (`VerseHighLight.isHighlighted`) — flips "Highlight" to "Remove".
        var isHighlighted: ([Int]) -> Bool
        var onAskEmet: ([Int]) -> Void
        var onHighlight: ([Int]) -> Void
        var onRemoveHighlight: ([Int]) -> Void
        var onShare: () -> Void
        var onNotes: () -> Void
    }

    let displayText: String
    let baseColor: Color
    /// Overrides every word (the focused verse is drawn white).
    let forcedColor: Color?
    let wordColors: [Int: Color]
    let fontSize: CGFloat
    let actions: Actions

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The verse text is not a link/data-detector surface.
        view.dataDetectorTypes = []
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let key = ContentKey(
            text: displayText,
            base: UIColor(baseColor).description,
            forced: forcedColor.map { UIColor($0).description },
            words: wordColors.mapValues { UIColor($0).description },
            size: fontSize
        )
        // Re-assigning the text drops the user's selection, so only do it when
        // something visible changed.
        guard coordinator.lastKey != key else { return }
        coordinator.lastKey = key
        view.attributedText = attributedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Attributed text

    private func attributedText() -> NSAttributedString {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont(name: "HelveticaNeue-Light", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .light)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.35
        paragraph.alignment = .natural

        let base = forcedColor.map(UIColor.init) ?? UIColor(baseColor)
        let result = NSMutableAttributedString(
            string: displayText,
            attributes: [.font: font, .foregroundColor: base, .paragraphStyle: paragraph]
        )
        if forcedColor == nil {
            for word in VerseWords.words(in: displayText) where word.range.length > 0 {
                if let color = wordColors[word.index] {
                    result.addAttribute(.foregroundColor, value: UIColor(color), range: word.range)
                }
            }
        }
        return result
    }

    fileprivate struct ContentKey: Equatable {
        let text: String
        let base: String
        let forced: String?
        let words: [Int: String]
        let size: CGFloat
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableVerseText
        fileprivate var lastKey: ContentKey?

        init(parent: SelectableVerseText) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let indices = VerseWords.indices(in: parent.displayText, selection: range)
            let actions = parent.actions
            let highlighted = !indices.isEmpty && actions.isHighlighted(indices)

            func item(_ title: String, _ handler: @escaping () -> Void) -> UIAction {
                UIAction(title: title) { [weak textView] _ in
                    handler()
                    // Menu taps shouldn't leave the selection handles behind.
                    textView?.selectedTextRange = nil
                }
            }

            var children: [UIMenuElement] = [
                item(String(localized: "Ask Emet")) { actions.onAskEmet(indices) },
                item(highlighted ? String(localized: "Remove") : String(localized: "Highlight")) {
                    if highlighted { actions.onRemoveHighlight(indices) } else { actions.onHighlight(indices) }
                },
                item(String(localized: "Share")) { actions.onShare() },
            ]
            children.append(UIAction(title: String(localized: "Select All")) { [weak textView] _ in
                textView?.selectAll(nil)
            })
            children.append(item(String(localized: "Notes")) { actions.onNotes() })
            return UIMenu(children: children)
        }
    }
}
