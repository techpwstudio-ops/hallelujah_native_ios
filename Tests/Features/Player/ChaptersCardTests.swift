import Testing
@testable import Hallelujah

/// Which rows the inline chapters card shows while collapsed, and the progress
/// bar of the current chapter.
struct ChaptersCardTests {
    @Test func collapsedCardStartsAtTheCurrentChapter() {
        #expect(ChaptersCard.collapsedRange(count: 10, current: 4) == 4..<7)
    }

    @Test func collapsedCardStartsAtTheFirstChapterBeforeAnyHasStarted() {
        #expect(ChaptersCard.collapsedRange(count: 10, current: nil) == 0..<3)
    }

    @Test func collapsedCardIsPulledBackNearTheEndSoItIsNeverShort() {
        #expect(ChaptersCard.collapsedRange(count: 10, current: 9) == 7..<10)
        #expect(ChaptersCard.collapsedRange(count: 10, current: 8) == 7..<10)
        #expect(ChaptersCard.collapsedRange(count: 10, current: 7) == 7..<10)
    }

    @Test func aShortListShowsEveryChapter() {
        #expect(ChaptersCard.collapsedRange(count: 2, current: 1) == 0..<2)
        #expect(ChaptersCard.collapsedRange(count: 3, current: 2) == 0..<3)
    }

    @Test func noChaptersShowNoRows() {
        #expect(ChaptersCard.collapsedRange(count: 0, current: nil).isEmpty)
    }

    @Test func aCurrentIndexOutsideTheListIsClamped() {
        #expect(ChaptersCard.collapsedRange(count: 5, current: 99) == 2..<5)
        #expect(ChaptersCard.collapsedRange(count: 5, current: -3) == 0..<3)
    }

    @Test func progressIsTheShareOfTheChapterPlayed() {
        #expect(ChaptersCard.progress(positionMs: 50_000, startMs: 0, endMs: 100_000) == 0.5)
        #expect(ChaptersCard.progress(positionMs: 130_000, startMs: 100_000, endMs: 200_000) == 0.3)
    }

    @Test func progressStaysBetweenZeroAndOne() {
        #expect(ChaptersCard.progress(positionMs: 5_000, startMs: 10_000, endMs: 20_000) == 0)
        #expect(ChaptersCard.progress(positionMs: 25_000, startMs: 10_000, endMs: 20_000) == 1)
    }

    @Test func progressIsUnknownWhileTheChapterEndIsUnknown() {
        #expect(ChaptersCard.progress(positionMs: 5_000, startMs: 0, endMs: nil) == nil)
        #expect(ChaptersCard.progress(positionMs: 5_000, startMs: 10_000, endMs: 10_000) == nil)
    }
}
