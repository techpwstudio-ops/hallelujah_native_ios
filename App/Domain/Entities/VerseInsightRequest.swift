import Foundation

/// T60 — an "explain this to me" question built from a
/// `VerseInsightTarget`. Ports the Flutter app's
/// `lib/models/ai/verse_insight_request.dart`.
///
/// Holds the finished prompt text and the labels the dialog shows, so every
/// surface that can ask about a verse goes through the same wording and the
/// same reference format. Today that's only the Bible reader's "Ask Emet"
/// context-menu action (T60's own scope); a verse-of-day surface is
/// expected to reuse this same type later once `VerseInsightTarget`'s own
/// `fromVerseOfDay` factory lands.
struct VerseInsightRequest: Sendable, Equatable {
    /// The words the reader selected. Empty when the whole verse was
    /// picked — the prompt then asks about the verse as a whole. T60's only
    /// real call site (`VerseRowView`'s whole-row `.contextMenu`) always
    /// passes an empty string here: SwiftUI's `Text`/`.contextMenu` exposes
    /// no selection-range API equivalent to Flutter's
    /// `EditableTextState`/`SelectionChangedCause` that a context-menu
    /// callback could read a substring out of, so "selected text" isn't
    /// reachable from this codebase's reader UI as it exists today. The
    /// whole-verse vs. selection branch below is still fully ported (not
    /// dead code) — it activates for any future caller that does have real
    /// selected text to pass.
    let selectedText: String

    /// Full text of the verse the selection sits in, always sent as
    /// context.
    let verseText: String

    /// Human-readable location, e.g. `Genesis 1:3`.
    let reference: String

    /// Bible language the verse is being read in. Doubles as the language
    /// the answer is asked to come back in.
    let language: String

    /// Builds the question from a `VerseInsightTarget`. `language`
    /// overrides the target's own `languageName` when passed.
    static func fromTarget(_ target: VerseInsightTarget, selectedText: String = "", language: String? = nil) -> VerseInsightRequest {
        let resolvedLanguage = firstNonBlank([language, target.languageName]) ?? "English"

        return VerseInsightRequest(
            selectedText: cleanSelection(selectedText, target: target),
            verseText: target.text,
            reference: reference(for: target, language: resolvedLanguage),
            language: resolvedLanguage
        )
    }

    var isWholeVerse: Bool {
        selectedText.isEmpty || selectedText == verseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Title the thread carries in Emet history. Not currently wired
    /// anywhere: see this feature's `VerseInsightViewModel` doc comment for
    /// why — `AIChatRepository.createConversation()` takes no title
    /// parameter to pass this to.
    var title: String {
        let base = isWholeVerse ? reference : "\(reference) — \(selectedText)"
        guard base.count > 60 else { return base }
        return String(base.prefix(60)) + "..."
    }

    /// The message sent to the AI. Plain text on the existing send
    /// endpoint — no new backend contract.
    var prompt: String {
        var lines = [
            "I am reading \(reference) in the \(language) Bible.",
            "",
            "Verse: \"\(verseText.trimmingCharacters(in: .whitespacesAndNewlines))\"",
        ]

        if !isWholeVerse {
            lines.append("I selected: \"\(selectedText)\"")
            lines.append("")
            lines.append(
                "Explain \"\(selectedText)\" as it is used in this verse: what it "
                    + "means, the background or context behind it, and how I can apply "
                    + "it in daily life."
            )
        } else {
            lines.append("")
            lines.append(
                "Explain this verse: what it means, the background or "
                    + "context behind it, and how I can apply it in daily life."
            )
        }

        lines.append("Keep it short and easy to understand, and answer in \(language).")
        return lines.joined(separator: "\n")
    }

    // MARK: - Building blocks

    private static func firstNonBlank(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// `12. In the beginning` → `In the beginning`. The number only counts
    /// as a prefix when a separator or the end of the selection follows it,
    /// so `12th day` in verse 12 is left alone.
    private static func cleanSelection(_ raw: String, target: VerseInsightTarget) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let verseNumber = target.verseNumber else { return trimmed }

        let pattern = "^\(verseNumber)\\.?(\\s+|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return trimmed }

        let nsTrimmed = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsTrimmed.length)
        guard let match = regex.firstMatch(in: trimmed, range: fullRange), match.range.location == 0 else {
            return trimmed
        }

        let stripped = nsTrimmed.replacingCharacters(in: match.range, with: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `Genesis 1:3` — the surface's own book name when it has one,
    /// otherwise just the `chapter:verse` location, or `"this verse"` if
    /// even that's unavailable. See `VerseInsightTarget`'s own doc comment
    /// for why this doesn't also fall back to a Bible-data lookup the way
    /// Flutter's `_referenceOf` does.
    private static func reference(for target: VerseInsightTarget, language: String) -> String {
        let bookName = target.bookName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = [target.chapterNumber, target.verseNumber]
            .compactMap { $0 }
            .map(String.init)
            .joined(separator: ":")

        var parts: [String] = []
        if let bookName, !bookName.isEmpty { parts.append(bookName) }
        if !location.isEmpty { parts.append(location) }

        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? "this verse" : joined
    }
}
