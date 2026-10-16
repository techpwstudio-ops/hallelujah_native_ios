import Foundation
import Testing
@testable import GHallelujah

struct VerseHighlightTests {
    private let display = "3. In the beginning God"   // words: "3.", "In", "the", "beginning", "God"

    @Test func wordRangesFollowSingleSpaces() {
        let words = VerseWords.words(in: display)
        #expect(words.map(\.index) == [0, 1, 2, 3, 4])
        #expect(words[1].range == NSRange(location: 3, length: 2))
        #expect(words[4].range == NSRange(location: 20, length: 3))
        #expect(VerseWords.count(in: display) == 5)
    }

    @Test func aSelectionTouchingPartOfAWordTakesTheWholeWord() {
        // "beginning" starts at 10; select its middle only.
        #expect(VerseWords.indices(in: display, selection: NSRange(location: 12, length: 3)) == [3])
        // From inside "In" to inside "the".
        #expect(VerseWords.indices(in: display, selection: NSRange(location: 4, length: 5)) == [1, 2])
    }

    @Test func aCollapsedSelectionPicksNothing() {
        #expect(VerseWords.indices(in: display, selection: NSRange(location: 5, length: 0)).isEmpty)
    }

    @Test func selectedTextIsWidenedToWholeWords() {
        #expect(VerseWords.selectedText(in: display, indices: [1, 2]) == "In the")
    }

    @Test func wordsAreMeasuredInUTF16ForNonLatinScripts() {
        let hindi = "1. आदि में"
        let words = VerseWords.words(in: hindi)
        #expect(words.count == 3)
        #expect(words[1].range.location == 3)
        #expect(words[2].range.location == (hindi as NSString).length - 2)
    }

    @Test func applyingAColourTouchesOnlyTheChosenWords() {
        let highlight = VerseHighlight(id: "h", verseId: "v", words: [.init(index: 1, colorHex: "#FFABAB")])
        let words = highlight.applying(colorHex: "#ABFFCD", to: [1, 2], wordCount: 5)
        #expect(words == [.init(index: 1, colorHex: "#ABFFCD"), .init(index: 2, colorHex: "#ABFFCD")])
    }

    @Test func removingDropsOnlyTheChosenWords() {
        let highlight = VerseHighlight(id: "h", verseId: "v", words: [
            .init(index: 1, colorHex: "#FFABAB"), .init(index: 2, colorHex: "#FFABAB"), .init(index: 3, colorHex: "#FFDDAB"),
        ])
        #expect(highlight.removing(indices: [2], wordCount: 5).map(\.index) == [1, 3])
        #expect(highlight.removing(indices: [1, 2, 3], wordCount: 5).isEmpty)
    }

    @Test func aWholeVerseHighlightExpandsBeforeAWordEdit() {
        let whole = VerseHighlight(id: "h", verseId: "v", colorHex: "#FFABAB")
        #expect(whole.colorHex(forWord: 3) == "#FFABAB")
        #expect(whole.isHighlighted(anyOf: [2]))

        let edited = whole.removing(indices: [1], wordCount: 3)
        #expect(edited == [.init(index: 0, colorHex: "#FFABAB"), .init(index: 2, colorHex: "#FFABAB")])

        let recoloured = whole.applying(colorHex: "#BCABFF", to: [0], wordCount: 3)
        #expect(recoloured.map(\.colorHex) == ["#BCABFF", "#FFABAB", "#FFABAB"])
    }

    @Test func isHighlightedIsTrueIfAnySelectedWordIs() {
        let highlight = VerseHighlight(id: "h", verseId: "v", words: [.init(index: 2, colorHex: "#FFABAB")])
        #expect(highlight.isHighlighted(anyOf: [1, 2]))
        #expect(!highlight.isHighlighted(anyOf: [0, 1]))
        #expect(!highlight.isHighlighted(anyOf: []))
    }

    @Test func decodesTheLegacySingleColourCacheShape() throws {
        let json = Data(#"{"id":"h","verseId":"v","colorHex":"#FFABAB"}"#.utf8)
        let decoded = try JSONDecoder().decode(VerseHighlight.self, from: json)
        #expect(decoded.words == [.init(index: nil, colorHex: "#FFABAB")])

        let roundTrip = try JSONDecoder().decode(VerseHighlight.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func serverRowMapsToWordsAndAnEmptyRowToNil() throws {
        let row = Data(#"{"id":"h","verseId":"v","highlights":[{"id":"w","index":2,"color":"#FFDDAB"}]}"#.utf8)
        let dto = try JSONDecoder().decode(VerseHighlightDTO.self, from: row)
        #expect(dto.toDomain()?.words == [.init(index: 2, colorHex: "#FFDDAB")])

        let empty = Data(#"{"id":"h","verseId":"v","highlights":[]}"#.utf8)
        #expect(try JSONDecoder().decode(VerseHighlightDTO.self, from: empty).toDomain() == nil)
    }
}
