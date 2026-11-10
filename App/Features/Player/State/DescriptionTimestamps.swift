import Foundation

/// Finds the timestamps in an episode description that should be tappable (Phase 1).
/// A pure function with no UI imports.
///
/// A token is a link only when it is a whole `M:SS`, `MM:SS`, `H:MM:SS` or
/// `HH:MM:SS` timestamp and its time equals the `startMs` of some chapter. So
/// `John 10:11` stays plain text unless a chapter starts at exactly 10:11.
///
/// What counts as a whole token mirrors the backend parser
/// (`backend/src/services/chapters/parseChapters.js`), line by line:
/// - A letter or digit touching either end, a colon in front, a colon and a digit
///   behind, or a decimal part means the token is part of something longer
///   (`v2:30`, `1:20:5`, `10:30.5`, `3.2:30`). A colon and a space behind is only
///   a separator, so `4:00: Intro` is fine.
/// - Seconds must be below 60, and so must minutes when there are hours.
/// - `7:00 PM` and `7:00 p.m.` are times of day, and `3:16-18` is a verse range.
/// - Digits of the Indian scripts count as digits (`१०:३०`).
enum DescriptionTimestamps {
    /// One tappable timestamp: where it is in the text, and its time.
    struct Link: Equatable {
        let range: Range<String.Index>
        let milliseconds: Int
    }

    /// The tappable timestamps in `text`, left to right. Empty when there are no
    /// chapters, so such episodes show the description exactly as before.
    static func links(in text: String, chapterStartsMs: [Int]) -> [Link] {
        guard !chapterStartsMs.isEmpty, !text.isEmpty else { return [] }
        let starts = Set(chapterStartsMs)
        let view = text.unicodeScalars
        let scalars = Array(view)
        let indices = Array(view.indices) + [view.endIndex]

        var links: [Link] = []
        var position = 0
        while position < scalars.count {
            guard let token = token(in: scalars, at: position) else {
                position += 1
                continue
            }
            if let milliseconds = token.milliseconds, starts.contains(milliseconds) {
                links.append(Link(range: indices[position]..<indices[token.end], milliseconds: milliseconds))
            }
            position = token.end
        }
        return links
    }

    // MARK: - Link URLs

    /// The private scheme a timestamp link carries, so a tap never leaves the app.
    static let scheme = "hallelujah-chapter"

    /// The URL a timestamp link opens: `hallelujah-chapter://seek/<ms>`.
    static func url(forMilliseconds milliseconds: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "seek"
        components.path = "/\(milliseconds)"
        return components.url
    }

    /// The time a timestamp link's URL stands for, or `nil` for any other URL.
    static func milliseconds(from url: URL) -> Int? {
        guard url.scheme == scheme, url.host == "seek" else { return nil }
        guard let value = Int(url.path.dropFirst()), value >= 0 else { return nil }
        return value
    }

    // MARK: - Scanning

    /// A token that has the shape of a timestamp. `milliseconds` is nil when the
    /// shape matched but the token is rejected (a seconds value of 60 or more,
    /// a time of day, a verse range). The scan still moves past it, as the backend does.
    private struct Token {
        let end: Int
        let milliseconds: Int?
    }

    private static func token(in scalars: [Unicode.Scalar], at start: Int) -> Token? {
        guard isTokenStart(scalars, at: start), let shape = shape(in: scalars, at: start) else { return nil }
        let end = shape.end
        let hours = shape.third == nil ? 0 : shape.first
        let minutes = shape.third == nil ? shape.first : shape.second
        let seconds = shape.third ?? shape.second

        guard seconds < 60, shape.third == nil || minutes < 60,
              !startsWithTimeOfDay(scalars, at: end),
              !startsWithVerseRange(scalars, at: end)
        else { return Token(end: end, milliseconds: nil) }
        return Token(end: end, milliseconds: (hours * 3600 + minutes * 60 + seconds) * 1000)
    }

    /// Nothing in front that makes the token part of a longer one.
    private static func isTokenStart(_ scalars: [Unicode.Scalar], at start: Int) -> Bool {
        guard start > 0 else { return true }
        let previous = scalars[start - 1]
        if isLetterOrNumber(previous) || previous == ":" { return false }
        if previous == "." || previous == "," {
            return start < 2 || digitValue(scalars, at: start - 2) == nil
        }
        return true
    }

    /// The digits of `M:SS` or `H:MM:SS` at `start` and where the token ends, or
    /// `nil` when the shape is wrong or something behind it makes it part of a longer token.
    private static func shape(
        in scalars: [Unicode.Scalar],
        at start: Int
    ) -> (first: Int, second: Int, third: Int?, end: Int)? {
        var position = start
        guard var first = digitValue(scalars, at: position) else { return nil }
        position += 1
        if let next = digitValue(scalars, at: position) {
            first = first * 10 + next
            position += 1
        }
        guard position < scalars.count, scalars[position] == ":" else { return nil }
        position += 1
        guard let minuteTens = digitValue(scalars, at: position),
              let minuteOnes = digitValue(scalars, at: position + 1)
        else { return nil }
        let second = minuteTens * 10 + minuteOnes
        position += 2

        var third: Int?
        if position < scalars.count, scalars[position] == ":",
           let tens = digitValue(scalars, at: position + 1), let ones = digitValue(scalars, at: position + 2) {
            third = tens * 10 + ones
            position += 3
        }

        if position < scalars.count {
            let next = scalars[position]
            if isLetterOrNumber(next) { return nil }
            if next == ":" || next == "." || next == ",", digitValue(scalars, at: position + 1) != nil { return nil }
        }
        return (first, second, third, position)
    }

    /// "7:00 PM", "7:00 p.m.": case-sensitive on purpose, as in the backend
    /// ("0:00 Am I saved?" is a title). Stays on the same line.
    private static func startsWithTimeOfDay(_ scalars: [Unicode.Scalar], at position: Int) -> Bool {
        var cursor = position
        while cursor < scalars.count, isInlineSpace(scalars[cursor]) { cursor += 1 }
        guard cursor + 1 < scalars.count else { return false }
        let letter = scalars[cursor]
        let upper = letter == "A" || letter == "P"
        let lower = letter == "a" || letter == "p"

        // "AM", "PM", "am", "pm", with no letter or digit after.
        let plainSecond: Unicode.Scalar = upper ? "M" : "m"
        if upper || lower, scalars[cursor + 1] == plainSecond,
           !isLetterOrNumber(scalar(scalars, at: cursor + 2)) {
            return true
        }

        // "A.M", "P.M", "a.m", "p.m", then an optional dot. With the dot or without it,
        // what follows "A.M" must not be a letter or digit, and a dot is neither.
        guard upper || lower, scalars[cursor + 1] == ".", cursor + 2 < scalars.count,
              scalars[cursor + 2] == plainSecond
        else { return false }
        return !isLetterOrNumber(scalar(scalars, at: cursor + 3))
    }

    /// "3:16-18": a dash and a number touching the timestamp, with no colon after that number.
    private static func startsWithVerseRange(_ scalars: [Unicode.Scalar], at position: Int) -> Bool {
        guard position < scalars.count, ["-", "\u{2013}", "\u{2014}"].contains(scalars[position]) else {
            return false
        }
        var cursor = position + 1
        guard digitValue(scalars, at: cursor) != nil else { return false }
        while digitValue(scalars, at: cursor) != nil { cursor += 1 }
        return cursor >= scalars.count || scalars[cursor] != ":"
    }

    // MARK: - Characters

    /// Code point of "0" in each Indian script that has its own digits.
    private static let indianZeros: [UInt32] = [
        0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66,
    ]

    /// 0 to 9 for an ASCII or Indian-script digit at `position`, else `nil`.
    private static func digitValue(_ scalars: [Unicode.Scalar], at position: Int) -> Int? {
        guard position >= 0, position < scalars.count else { return nil }
        let code = scalars[position].value
        if code >= 0x30, code <= 0x39 { return Int(code - 0x30) }
        for zero in indianZeros where code >= zero && code <= zero + 9 {
            return Int(code - zero)
        }
        return nil
    }

    /// The scalar at `position`, or a space past the end (not a letter or digit).
    private static func scalar(_ scalars: [Unicode.Scalar], at position: Int) -> Unicode.Scalar {
        position < scalars.count ? scalars[position] : " "
    }

    /// `\p{L}` or `\p{N}`.
    private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            true
        default:
            false
        }
    }

    /// Whitespace that does not end a line. The backend reads one line at a time.
    private static func isInlineSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace && !isLineBreak(scalar)
    }

    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
