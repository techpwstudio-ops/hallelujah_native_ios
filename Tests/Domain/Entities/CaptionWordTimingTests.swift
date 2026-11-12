import Foundation
import Testing
@testable import Hallelujah

/// Word timing for caption-sourced transcripts. Same cases as the Flutter
/// `word_timing_test.dart`, so the two apps cannot drift apart.
struct CaptionWordTimingTests {
    /// The backend's caption split (`cueWords.js`): each word gets a share of
    /// the caption in proportion to its code points, and the words touch.
    private func captions(_ cues: [(Int, Int, String)]) -> (starts: [Int], ends: [Int], words: [String]) {
        var starts: [Int] = []
        var ends: [Int] = []
        var words: [String] = []
        for (cueStart, cueEnd, line) in cues {
            let tokens = line.split(separator: " ").map(String.init)
            let total = tokens.reduce(0) { $0 + $1.unicodeScalars.count }
            let duration = Double(cueEnd - cueStart)
            var consumed = 0
            for (i, token) in tokens.enumerated() {
                starts.append(cueStart + Int((duration * Double(consumed) / Double(total)).rounded()))
                consumed += token.unicodeScalars.count
                ends.append(i + 1 < tokens.count
                    ? cueStart + Int((duration * Double(consumed) / Double(total)).rounded())
                    : cueEnd)
                words.append(token)
            }
        }
        return (starts, ends, words)
    }

    @Test func touchingCaptionsWithDifferentPaceAreToldApart() {
        let c = captions([
            (1000, 4200, "In the beginning God created the heaven and the earth."),
            (4200, 8100, "And the earth was without form, and void; and darkness."),
            (8500, 9000, "Amen."),
        ])
        let lines = CaptionWordTiming.captionLines(startsMs: c.starts, endsMs: c.ends, words: c.words)
        #expect(lines == [0...9, 10...19, 20...20])
    }

    @Test func everyLineKeepsItsExactStartAndEnd() {
        var c = captions([
            (1000, 4200, "In the beginning God created the heaven and the earth."),
            (4200, 8100, "And the earth was without form, and void; and darkness."),
        ])
        CaptionWordTiming.refine(startsMs: &c.starts, endsMs: &c.ends, words: c.words)
        #expect(c.starts[0] == 1000)
        #expect(c.ends[9] == 4200)
        #expect(c.starts[10] == 4200)
        #expect(c.ends.last == 8100)
    }

    @Test func startsNeverGoBackwards() {
        var c = captions([
            (0, 2500, "నమస్కారం అందరికీ, ఈ రోజు యోహాను 3:16 చదువుదాం."),
            (2500, 4500, "नमस्ते दोस्तों, आज हम प्रार्थना करेंगे।"),
        ])
        CaptionWordTiming.refine(startsMs: &c.starts, endsMs: &c.ends, words: c.words)
        for i in c.words.indices {
            #expect(c.ends[i] > c.starts[i])
            if i > 0 { #expect(c.starts[i] >= c.starts[i - 1]) }
        }
    }

    @Test func aPauseFollowsAComma() throws {
        var c = captions([(0, 4000, "And the earth was without form, and void and darkness")])
        CaptionWordTiming.refine(startsMs: &c.starts, endsMs: &c.ends, words: c.words)
        let form = try #require(c.words.firstIndex(of: "form,"))
        #expect(c.starts[form + 1] - c.ends[form] > 50)
        #expect(c.starts[form + 2] == c.ends[form + 1])
    }

    @Test func shortWordsGainTimeAndSilentSpellingsLose() throws {
        var c = captions([(0, 3000, "I walked through the strength of a valley")])
        let before = c.words.indices.map { c.ends[$0] - c.starts[$0] }
        CaptionWordTiming.refine(startsMs: &c.starts, endsMs: &c.ends, words: c.words)
        let after = c.words.indices.map { c.ends[$0] - c.starts[$0] }
        let i = try #require(c.words.firstIndex(of: "I"))
        let strength = try #require(c.words.firstIndex(of: "strength"))
        #expect(after[i] > before[i])
        #expect(after[strength] < before[strength])
    }

    @Test func beatsBySpokenVowelsSyllablesAndDigits() {
        let beat = CaptionWordTiming.wordBeat
        #expect(abs(CaptionWordTiming.spokenBeats("నమస్కారం") - (beat + 4)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("ఈ") - (beat + 1)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("हम") - (beat + 1)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("नमस्ते") - (beat + 3)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("beginning") - (beat + 3)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("face") - (beat + 1)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("Bible") - (beat + 2)) < 1e-9)
        #expect(abs(CaptionWordTiming.spokenBeats("3:16") - (beat + 3)) < 1e-9)
        #expect(CaptionWordTiming.pauseBeats(after: "earth.") == CaptionWordTiming.longPauseBeats)
        #expect(CaptionWordTiming.pauseBeats(after: "said,\"") == CaptionWordTiming.shortPauseBeats)
        #expect(CaptionWordTiming.pauseBeats(after: "earth") == 0)
    }

    @Test func realWordTimingIsLeftAlone() {
        var starts = [1200, 1500, 1950, 2140, 2640, 3040]
        var ends = [1460, 1910, 2100, 2600, 3000, 3500]
        CaptionWordTiming.refine(
            startsMs: &starts, endsMs: &ends,
            words: ["Rob,", "thanks", "for", "joining", "us", "today."]
        )
        #expect(starts == [1200, 1500, 1950, 2140, 2640, 3040])
        #expect(ends == [1460, 1910, 2100, 2600, 3000, 3500])
    }

    @Test func aMostlyRealFileIsNotTouched() {
        var starts = [0, 100, 300, 900, 1500, 2100]
        var ends = [100, 300, 800, 1400, 2000, 2600]
        CaptionWordTiming.refine(
            startsMs: &starts, endsMs: &ends,
            words: ["a", "ab", "word", "other", "more", "last"]
        )
        #expect(starts == [0, 100, 300, 900, 1500, 2100])
        #expect(ends == [100, 300, 800, 1400, 2000, 2600])
    }
}
