import Foundation

/// A verse's highlights at word granularity (`VerseHighLight` +
/// `HighlightedWordModel`, `lib/models/verse_highlight.dart`): one entry per
/// highlighted word index, each with its own colour — so a selection of a few
/// words colours only those words.
///
/// An entry with a `nil` index is the earlier whole-verse form (`{color}`
/// only); it reads as "every word not coloured individually" and is expanded
/// to explicit indices the moment a word-level edit is made.
struct VerseHighlight: Sendable, Equatable, Identifiable, Codable {
    struct Word: Sendable, Equatable, Codable {
        /// Index into the verse's display words (`VerseWords`); `nil` = whole verse.
        let index: Int?
        let colorHex: String
    }

    let id: String
    let verseId: String
    let words: [Word]

    init(id: String, verseId: String, words: [Word]) {
        self.id = id
        self.verseId = verseId
        self.words = words
    }

    /// The whole-verse form.
    init(id: String, verseId: String, colorHex: String) {
        self.init(id: id, verseId: verseId, words: [Word(index: nil, colorHex: colorHex)])
    }

    private enum CodingKeys: String, CodingKey { case id, verseId, words, colorHex }

    /// Decodes both the current shape and cached rows written when only a
    /// single `colorHex` was stored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        verseId = try c.decode(String.self, forKey: .verseId)
        if let words = try c.decodeIfPresent([Word].self, forKey: .words) {
            self.words = words
        } else {
            let hex = try c.decode(String.self, forKey: .colorHex)
            words = [Word(index: nil, colorHex: hex)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(verseId, forKey: .verseId)
        try c.encode(words, forKey: .words)
    }

    /// `hexToColor(index:)` — the colour of one word, `nil` when it has none.
    func colorHex(forWord index: Int) -> String? {
        words.first(where: { $0.index == index })?.colorHex
            ?? words.first(where: { $0.index == nil })?.colorHex
    }

    /// `isHighlighted(indexes)` — true if ANY of the words is highlighted.
    func isHighlighted(anyOf indices: [Int]) -> Bool {
        indices.contains { colorHex(forWord: $0) != nil }
    }

    /// Every whole-verse entry turned into explicit per-word entries.
    func expanded(wordCount: Int) -> [Word] {
        guard let whole = words.first(where: { $0.index == nil })?.colorHex else { return words }
        let explicit = Dictionary(
            words.compactMap { w in w.index.map { ($0, w.colorHex) } },
            uniquingKeysWith: { _, latest in latest }
        )
        return (0..<wordCount).map { Word(index: $0, colorHex: explicit[$0] ?? whole) }
    }

    /// The words after colouring `indices` with `colorHex` (replacing any
    /// colour they had), sorted by index.
    func applying(colorHex: String, to indices: [Int], wordCount: Int) -> [Word] {
        var byIndex = Dictionary(
            expanded(wordCount: wordCount).compactMap { w in w.index.map { ($0, w.colorHex) } },
            uniquingKeysWith: { _, latest in latest }
        )
        for index in indices { byIndex[index] = colorHex }
        return byIndex.keys.sorted().map { Word(index: $0, colorHex: byIndex[$0]!) }
    }

    /// The words after un-highlighting `indices`.
    func removing(indices: [Int], wordCount: Int) -> [Word] {
        let drop = Set(indices)
        return expanded(wordCount: wordCount).filter { $0.index.map { !drop.contains($0) } ?? false }
    }

    /// `applying` for a verse with no highlight yet.
    static func words(colorHex: String, for indices: [Int]) -> [Word] {
        Set(indices).sorted().map { Word(index: $0, colorHex: colorHex) }
    }
}

/// A verse's display words (`calculateWordIndices`,
/// `lib/helpers/calculateWordIndices.dart`): `"<n>. <text>"` split on single
/// spaces, so index 0 is the verse number. Ranges are UTF-16 (`NSRange`) so
/// they line up with `UITextView` selections.
enum VerseWords {
    struct Word: Equatable {
        let index: Int
        let range: NSRange
    }

    static func displayText(verseNumber: Int, text: String) -> String {
        "\(verseNumber). \(text)"
    }

    static func words(in display: String) -> [Word] {
        var result: [Word] = []
        var location = 0
        for (index, token) in display.components(separatedBy: " ").enumerated() {
            let length = (token as NSString).length
            result.append(Word(index: index, range: NSRange(location: location, length: length)))
            location += length + 1
        }
        return result
    }

    static func count(in display: String) -> Int {
        display.components(separatedBy: " ").count
    }

    /// `getSelectedIndexes` — every word the selection touches (a partly
    /// selected word counts whole). Empty for a collapsed selection.
    static func indices(in display: String, selection: NSRange) -> [Int] {
        guard selection.length > 0 else { return [] }
        return words(in: display)
            .filter { $0.range.length > 0 && NSIntersectionRange($0.range, selection).length > 0 }
            .map(\.index)
    }

    /// The selected text widened to whole words (what "Ask Emet" is sent).
    static func selectedText(in display: String, indices: [Int]) -> String {
        let all = display.components(separatedBy: " ")
        return indices.compactMap { all.indices.contains($0) ? all[$0] : nil }.joined(separator: " ")
    }
}
