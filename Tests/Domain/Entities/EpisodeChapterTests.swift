import Foundation
import Testing
@testable import Hallelujah

/// How a chapter ends and what it is called, when the server leaves them out.
struct EpisodeChapterTests {
    // MARK: - Effective end

    @Test func theServersEndWinsOverThePlayerDuration() {
        let chapter = EpisodeChapter(startMs: 0, endMs: 5000, title: "Intro")

        #expect(chapter.effectiveEndMs(playerDurationMs: 9000) == 5000)
        #expect(chapter.effectiveEndMs(playerDurationMs: nil) == 5000)
    }

    @Test func withNoEndTheChapterEndsAtThePlayerDuration() {
        let chapter = EpisodeChapter(startMs: 5000, endMs: nil, title: "Outro")

        #expect(chapter.effectiveEndMs(playerDurationMs: 9000) == 9000)
    }

    @Test func withNoEndAndNoDurationTheChapterIsOpenEnded() {
        let chapter = EpisodeChapter(startMs: 5000, endMs: nil, title: "Outro")

        #expect(chapter.effectiveEndMs(playerDurationMs: nil) == nil)
    }

    @Test func aDurationAtOrBeforeTheStartIsNotAnEnd() {
        let chapter = EpisodeChapter(startMs: 5000, endMs: nil, title: "Outro")

        #expect(chapter.effectiveEndMs(playerDurationMs: 5000) == nil)
        #expect(chapter.effectiveEndMs(playerDurationMs: 100) == nil)
    }

    @Test func aDurationInSecondsBecomesWholeMilliseconds() {
        #expect(PlayerSeekBar.milliseconds(of: 3600) == 3_600_000)
        #expect(PlayerSeekBar.milliseconds(of: 1.2345) == 1235)
    }

    @Test func anUnknownDurationHasNoMilliseconds() {
        #expect(PlayerSeekBar.milliseconds(of: 0) == nil)
        #expect(PlayerSeekBar.milliseconds(of: -3) == nil)
        #expect(PlayerSeekBar.milliseconds(of: .nan) == nil)
        #expect(PlayerSeekBar.milliseconds(of: .infinity) == nil)
    }

    // MARK: - Display title

    @Test func aTitleIsShownAsItIs() {
        let chapter = EpisodeChapter(startMs: 0, endMs: 5000, title: "Intro")

        #expect(chapter.hasTitle)
        #expect(chapter.displayTitle(at: 0) == "Intro")
    }

    @Test func anEmptyTitleShowsChapterNumberCountedFromOne() {
        let chapter = EpisodeChapter(startMs: 0, endMs: 5000, title: "")

        // Not compared with `String(localized:)`: the app module shadows it, so a test
        // that imports the module sees two candidates. The wording is locale-dependent.
        #expect(!chapter.hasTitle)
        #expect(!chapter.displayTitle(at: 2).isEmpty)
        #expect(chapter.displayTitle(at: 2).contains("3"))
        #expect(chapter.displayTitle(at: 0) != chapter.displayTitle(at: 1))
    }

    @Test func aBlankTitleCountsAsEmpty() {
        let chapter = EpisodeChapter(startMs: 0, endMs: 5000, title: "  \n")

        #expect(!chapter.hasTitle)
        #expect(chapter.displayTitle(at: 0).contains("1"))
    }
}
