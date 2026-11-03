import Testing
@testable import Hallelujah

/// `TimelineIndex` lookups. Words: 1000-1400 "a", 1500-1900 "b", 2000-2400 "c".
struct TimelineIndexTests {
    private let transcript = EpisodeTranscriptFile(
        version: 1,
        language: "en",
        startsMs: [1000, 1500, 2000],
        endsMs: [1400, 1900, 2400],
        words: ["a", "b", "c"],
        segments: [
            EpisodeTranscriptFile.Segment(speaker: "S1", wordRange: 0..<2),
            EpisodeTranscriptFile.Segment(speaker: "S2", wordRange: 2..<3),
        ]
    )

    private func chapter(_ id: String, _ start: Int, _ end: Int) -> EpisodeChapter {
        EpisodeChapter(id: id, startMs: start, endMs: end, title: id, imageURL: nil, linkURL: nil)
    }

    @Test func beforeTheFirstWordThereIsNoActiveWord() {
        #expect(TimelineIndex(chapters: [], transcript: transcript).activeWordIndex(positionMs: 500) == nil)
    }

    @Test func insideAWordThatWord() {
        #expect(TimelineIndex(chapters: [], transcript: transcript).activeWordIndex(positionMs: 1200) == 0)
    }

    @Test func inAGapTheLastWordThatStartedIsActive() {
        #expect(TimelineIndex(chapters: [], transcript: transcript).activeWordIndex(positionMs: 1450) == 0)
    }

    @Test func exactlyOnAStartTheWordStarts() {
        #expect(TimelineIndex(chapters: [], transcript: transcript).activeWordIndex(positionMs: 1500) == 1)
    }

    @Test func afterTheLastWordItStaysOnTheLastWord() {
        #expect(TimelineIndex(chapters: [], transcript: transcript).activeWordIndex(positionMs: 9000) == 2)
    }

    @Test func positiveOffsetShiftsWordsLater() {
        let index = TimelineIndex(chapters: [], transcript: transcript, offsetMs: 250)
        #expect(index.activeWordIndex(positionMs: 1249) == nil)
        #expect(index.activeWordIndex(positionMs: 1250) == 0)
    }

    @Test func negativeOffsetShiftsWordsEarlier() {
        let index = TimelineIndex(chapters: [], transcript: transcript, offsetMs: -250)
        #expect(index.activeWordIndex(positionMs: 750) == 0)
    }

    @Test func noTranscriptMeansNoWord() {
        let index = TimelineIndex(chapters: [chapter("a", 0, 5000)])
        #expect(index.activeWordIndex(positionMs: 1200) == nil)
        #expect(index.isSpeaking(positionMs: 1200) == false)
        #expect(index.nextBoundaryMs(afterPositionMs: 1200) == nil)
    }

    @Test func activeChapterIsTheLastOneThatStarted() {
        let index = TimelineIndex(chapters: [chapter("a", 0, 74_000), chapter("b", 74_000, 100_000)])
        #expect(index.activeChapterIndex(positionMs: 0) == 0)
        #expect(index.activeChapterIndex(positionMs: 73_999) == 0)
        #expect(index.activeChapterIndex(positionMs: 74_000) == 1)
        #expect(index.activeChapterIndex(positionMs: 999_999) == 1)
    }

    @Test func noChaptersMeansNoActiveChapter() {
        #expect(TimelineIndex(chapters: []).activeChapterIndex(positionMs: 10) == nil)
    }

    @Test func speakerFollowsTheActiveWordsSegment() {
        let index = TimelineIndex(chapters: [], transcript: transcript)
        #expect(index.speakerLabel(forWord: 0) == "S1")
        #expect(index.speakerLabel(forWord: 2) == "S2")
        #expect(index.segmentIndex(forWord: 1) == 0)
        #expect(index.segmentIndex(forWord: 2) == 1)
    }

    @Test func shortGapsKeepTheBarsSpeaking() {
        let index = TimelineIndex(chapters: [], transcript: transcript)
        #expect(index.isSpeaking(positionMs: 1450))
    }

    @Test func aLongGapPausesTheBars() {
        let spaced = EpisodeTranscriptFile(
            version: 1,
            language: nil,
            startsMs: [0, 3000],
            endsMs: [1000, 4000],
            words: ["a", "b"],
            segments: [EpisodeTranscriptFile.Segment(speaker: nil, wordRange: 0..<2)]
        )
        let index = TimelineIndex(chapters: [], transcript: spaced)
        #expect(index.isSpeaking(positionMs: 500))
        #expect(index.isSpeaking(positionMs: 1500) == false)
        #expect(index.isSpeaking(positionMs: 3500))
        #expect(index.isSpeaking(positionMs: 4500) == false)
    }

    @Test func boundariesAreTheNextWordOrTheGapPause() {
        let index = TimelineIndex(chapters: [], transcript: transcript)
        // The next word starts at 1500, before the gap pause at 1400 + 700.
        #expect(index.nextBoundaryMs(afterPositionMs: 1200) == 1500)
        // After the last word the next change is the pause, 2400 + 700.
        #expect(index.nextBoundaryMs(afterPositionMs: 2600) == 3100)
        #expect(index.nextBoundaryMs(afterPositionMs: 3100) == nil)
    }

    @Test func boundariesIncludeTheOffset() {
        let index = TimelineIndex(chapters: [], transcript: transcript, offsetMs: 100)
        #expect(index.nextBoundaryMs(afterPositionMs: 1200) == 1600)
    }
}
