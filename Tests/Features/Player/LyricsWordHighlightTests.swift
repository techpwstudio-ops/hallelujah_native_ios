import SwiftUI
import Testing
@testable import Hallelujah

/// The word highlight on the active lyrics line. Same cases as Flutter's
/// `lyrics_line_item_test.dart`, so the two apps cannot drift apart.
@MainActor
struct LyricsWordHighlightTests {
    // MARK: When a line ends

    @Test func aLineEndsAtItsOwnEndWhenAfterItsStart() {
        #expect(CaptionWordTiming.lyricsLineEndMs(startTime: 10, endTime: 14, nextLineStart: 20) == 14000)
    }

    @Test func aLineIsCutAtTheNextLineWhenItsEndRunsPastIt() {
        #expect(CaptionWordTiming.lyricsLineEndMs(startTime: 10, endTime: 30, nextLineStart: 20) == 20000)
    }

    @Test func aLineWithNoEndRunsToTheNextLine() {
        #expect(CaptionWordTiming.lyricsLineEndMs(startTime: 10, endTime: 0, nextLineStart: 13) == 13000)
    }

    @Test func aLineWithNothingToGoOnRunsAFewSeconds() {
        #expect(CaptionWordTiming.lyricsLineEndMs(startTime: 10, endTime: 10, nextLineStart: nil) > 10000)
    }

    @Test func fractionalSecondsBecomeMilliseconds() {
        #expect(CaptionWordTiming.lyricsLineEndMs(startTime: 1.5, endTime: 3.25, nextLineStart: nil) == 3250)
    }

    // MARK: Spreading one line over its words

    @Test func wordsRunInOrderFromTheLineStartToItsEnd() throws {
        let times = CaptionWordTiming.spreadLineOverWords(["And", "I", "will", "catch", "up."],
                                                          startMs: 1000, endMs: 3000)
        #expect(times.count == 5)
        #expect(try #require(times.first).start == 1000)
        #expect(try #require(times.last).end == 3000)
        for i in 1..<times.count {
            #expect(times[i].start >= times[i - 1].end)
        }
    }

    @Test func nothingForAnEmptyLineOrALineWithNoTime() {
        #expect(CaptionWordTiming.spreadLineOverWords([], startMs: 0, endMs: 1000).isEmpty)
        #expect(CaptionWordTiming.spreadLineOverWords(["a"], startMs: 1000, endMs: 1000).isEmpty)
    }

    // MARK: The word being said

    @Test func theActiveWordFollowsThePlayhead() {
        let times = CaptionWordTiming.spreadLineOverWords(["God", "bless", "you"], startMs: 0, endMs: 3000)

        #expect(ActiveLyricsLine.wordIndex(at: 0, in: times) == 0)
        #expect(ActiveLyricsLine.wordIndex(at: 1500, in: times) == 1)
        #expect(ActiveLyricsLine.wordIndex(at: 2900, in: times) == 2)
        #expect(ActiveLyricsLine.wordIndex(at: -1, in: times) == -1)
    }

    @Test func saidWordsAreWhiteTheCurrentOneGoldAndTheRestDimmed() {
        let text = ActiveLyricsLine.coloured(["God", "bless", "you"], activeWord: 1)

        #expect(String(text.characters) == "God bless you")
        #expect(text.runs.map(\.foregroundColor) == [PlayerStyle.white, PlayerStyle.wordGold, PlayerStyle.whiteAlpha(0.38)])
    }

    @Test func theLineTimingComesFromTheNextLineWhenItsOwnEndIsMissing() {
        let lines = [
            LyricsTranscript(id: "a", startTime: 2, endTime: 0, text: "one", language: nil),
            LyricsTranscript(id: "b", startTime: 5, endTime: 9, text: "two", language: nil),
        ]
        let first = LyricsLineItem.WordTiming.of(lines, at: 0) { 0 }
        let last = LyricsLineItem.WordTiming.of(lines, at: 1) { 0 }

        #expect(first.startMs == 2000)
        #expect(first.endMs == 5000)
        #expect(last.endMs == 9000)
    }
}
