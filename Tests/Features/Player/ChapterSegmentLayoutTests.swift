import CoreGraphics
import Testing
@testable import Hallelujah

/// The chapter segments drawn along the seekbar track.
struct ChapterSegmentLayoutTests {
    @Test func widthsAreProportionalToLengthWithAGapBetween() {
        let segments = ChapterSegmentLayout.segments(spans: [(0, 1), (1, 4)], trackWidth: 103)

        #expect(segments.count == 2)
        #expect(segments[0].width == 25)
        #expect(segments[1].width == 75)
        #expect(segments[1].startX == 28)
    }

    @Test func segmentsFillTheWholeTrack() {
        let segments = ChapterSegmentLayout.segments(spans: [(0, 1), (1, 4), (4, 10)], trackWidth: 300)
        let end = segments.last.map { $0.startX + $0.width } ?? 0

        #expect(abs(end - 300) < 0.001)
    }

    @Test func oneChapterIsTheWholeTrack() {
        let segments = ChapterSegmentLayout.segments(spans: [(0, 100)], trackWidth: 200)

        #expect(segments.count == 1)
        #expect(segments[0].startX == 0)
        #expect(segments[0].width == 200)
    }

    @Test func aNarrowChapterMergesWithItsNeighbour() {
        let segments = ChapterSegmentLayout.segments(spans: [(0, 10), (10, 10.5), (10.5, 50)], trackWidth: 200)

        #expect(segments.count == 2)
        #expect(segments[1].startSeconds == 10)
        #expect(segments[1].endSeconds == 50)
    }

    @Test func aNarrowFinalChapterJoinsThePreviousOne() {
        let segments = ChapterSegmentLayout.segments(spans: [(0, 1), (1, 100), (100, 101)], trackWidth: 200)

        #expect(segments.count == 1)
        #expect(segments[0].endSeconds == 101)
    }

    @Test func twoHundredChaptersStillFillTheTrackWithNoSegmentUnderSixPoints() {
        let spans = (0..<200).map { (start: Double($0), end: Double($0 + 1)) }
        let segments = ChapterSegmentLayout.segments(spans: spans, trackWidth: 1000)

        #expect(segments.count < 200)
        #expect(segments.allSatisfy { $0.width >= ChapterSegmentLayout.defaultMinimumWidth })
        #expect(abs((segments.last.map { $0.startX + $0.width } ?? 0) - 1000) < 0.001)
    }

    @Test func emptyInputGivesNoSegments() {
        #expect(ChapterSegmentLayout.segments(spans: [], trackWidth: 100).isEmpty)
        #expect(ChapterSegmentLayout.segments(spans: [(0, 0)], trackWidth: 100).isEmpty)
    }

    @Test func playedFractionIsClampedToTheSegment() {
        let segment = ChapterSegmentLayout.Segment(id: 0, startX: 0, width: 100, startSeconds: 0, endSeconds: 10)

        #expect(segment.playedFraction(at: 5) == 0.5)
        #expect(segment.playedFraction(at: -1) == 0)
        #expect(segment.playedFraction(at: 20) == 1)
    }
}
