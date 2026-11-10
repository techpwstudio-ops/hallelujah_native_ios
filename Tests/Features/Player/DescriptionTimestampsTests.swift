import Foundation
import Testing
@testable import Hallelujah

/// Which timestamps in an episode description become links. A token links only
/// when it is a whole timestamp (the backend parser's rules) and equals a chapter start.
struct DescriptionTimestampsTests {
    /// The linked text, in order, for `text` against chapters starting at `starts`.
    private func linked(_ text: String, _ starts: [Int]) -> [String] {
        DescriptionTimestamps.links(in: text, chapterStartsMs: starts).map { String(text[$0.range]) }
    }

    // MARK: - Matching a chapter start

    @Test func aTimestampThatEqualsAChapterStartIsALink() {
        let text = "0:00 Intro\n1:14 Reading\n25:00 Sermon"
        let links = DescriptionTimestamps.links(in: text, chapterStartsMs: [0, 74_000, 1_500_000])

        #expect(links.map { String(text[$0.range]) } == ["0:00", "1:14", "25:00"])
        #expect(links.map(\.milliseconds) == [0, 74_000, 1_500_000])
    }

    @Test func onlyTimestampsThatMatchAChapterStartAreLinks() {
        #expect(linked("0:00 Intro\n1:14 Reading\n25:00 Sermon", [74_000]) == ["1:14"])
        #expect(linked("0:00 Intro\n1:15 Reading", [74_000]).isEmpty)
    }

    @Test func noChaptersMeansNoLinks() {
        #expect(linked("0:00 Intro\n1:14 Reading", []).isEmpty)
        #expect(DescriptionTimestamps.links(in: "", chapterStartsMs: [0]).isEmpty)
    }

    @Test func aVerseIsPlainTextUnlessAChapterStartsAtExactlyThatTime() {
        // John 10:11 reads as 10 min 11 s = 611 000 ms.
        #expect(linked("As in John 10:11, the good shepherd", [0, 74_000, 1_500_000]).isEmpty)
        #expect(linked("As in John 10:11, the good shepherd", [0, 611_000]) == ["10:11"])
    }

    @Test func aTimestampThatRepeatsLinksEveryTime() {
        #expect(linked("1:14 and again 1:14", [74_000]) == ["1:14", "1:14"])
    }

    @Test func hoursMinutesAndSeconds() {
        #expect(linked("1:05:30 Closing", [3_930_000]) == ["1:05:30"])
        #expect(linked("01:05:30 Closing", [3_930_000]) == ["01:05:30"])
        // The whole token is 1:14:30, so its 1:14 part is not a timestamp on its own.
        #expect(linked("1:14:30 Closing", [74_000]).isEmpty)
        #expect(linked("1:14:30 Closing", [4_470_000]) == ["1:14:30"])
    }

    @Test func minutesMayPassSixtyWithoutHours() {
        #expect(linked("75:30 Prayer", [4_530_000]) == ["75:30"])
    }

    // MARK: - Whole tokens only

    @Test(arguments: [
        "v2:30 note",
        "2:30pm",
        "a1:14",
        "1:14a",
        "1:20:5 start",
        "1:14.5",
        "1:14,5",
        "3.1:14",
        "3,1:14",
        ":1:14",
        "123:45",
        "1:145",
        "1:14:30:15",
    ])
    func aTokenTouchingOtherCharactersIsNotALink(text: String) {
        let everyReading = [74_000, 80_000, 150_000, 225_000, 1_425_000, 4_470_000]
        #expect(linked(text, everyReading).isEmpty, "\(text)")
    }

    @Test func aColonAndASpaceAfterIsOnlyASeparator() {
        #expect(linked("4:00: Intro", [240_000]) == ["4:00"])
    }

    @Test func punctuationAroundATimestampIsFine() {
        #expect(linked("(1:14) and [1:14] and \"1:14\" and 1:14. And 1:14, and 1:14!", [74_000]).count == 6)
        #expect(linked("1:14-Intro", [74_000]) == ["1:14"])
        #expect(linked("- 1:14 - Intro", [74_000]) == ["1:14"])
    }

    @Test func aTimestampRangeLinksBothEnds() {
        #expect(linked("0:00-1:14 Intro", [0, 74_000]) == ["0:00", "1:14"])
    }

    @Test func aTimestampAtTheStartOrEndOfTheTextIsALink() {
        #expect(linked("1:14", [74_000]) == ["1:14"])
        #expect(linked("Jump to 1:14", [74_000]) == ["1:14"])
    }

    // MARK: - Not times

    @Test func secondsAtOrAboveSixtyAreNotTimestamps() {
        #expect(linked("1:75 odd", [135_000]).isEmpty)
        #expect(linked("1:60 odd", [120_000]).isEmpty)
        #expect(linked("1:59 fine", [119_000]) == ["1:59"])
    }

    @Test func minutesAtOrAboveSixtyWithHoursAreNotTimestamps() {
        #expect(linked("1:75:00 odd", [5_100_000]).isEmpty)
        #expect(linked("1:60:00 odd", [7_200_000]).isEmpty)
    }

    @Test func aTimeOfDayIsNotATimestamp() {
        #expect(linked("Service at 7:00 PM", [420_000]).isEmpty)
        #expect(linked("Service at 7:00PM", [420_000]).isEmpty)
        #expect(linked("Service at 7:00 pm", [420_000]).isEmpty)
        #expect(linked("Service at 7:00 p.m. sharp", [420_000]).isEmpty)
        #expect(linked("Service at 7:00 A.M.", [420_000]).isEmpty)
        #expect(linked("Service at 7:00 a.m", [420_000]).isEmpty)
    }

    @Test func aWordThatOnlyStartsLikeAMeridiemIsStillATimestamp() {
        // Case-sensitive on purpose: "0:00 Am I saved?" is a chapter title.
        #expect(linked("0:00 Am I saved?", [0]) == ["0:00"])
        #expect(linked("7:00 AMEN", [420_000]) == ["7:00"])
        #expect(linked("7:00 pmx", [420_000]) == ["7:00"])
    }

    @Test func aTimeOfDayDoesNotReachIntoTheNextLine() {
        #expect(linked("7:00\nAM later", [420_000]) == ["7:00"])
    }

    @Test func aVerseRangeIsNotATimestamp() {
        #expect(linked("Mark 4:35-41", [275_000]).isEmpty)
        #expect(linked("John 3:16-18 and 3:16\u{2013}18 and 3:16\u{2014}18", [196_000]).isEmpty)
        #expect(linked("Mark 4:35-41a", [275_000]).isEmpty)
    }

    @Test func aDashThenAnotherTimestampIsNotAVerseRange() {
        #expect(linked("4:35-5:10 Reading", [275_000, 310_000]) == ["4:35", "5:10"])
    }

    // MARK: - Other scripts and text

    @Test func digitsOfTheIndianScriptsCount() {
        #expect(linked("\u{0967}:\u{0967}\u{096A} परिचय", [74_000]) == ["\u{0967}:\u{0967}\u{096A}"]) // Devanagari
        #expect(linked("\u{0C67}:\u{0C67}\u{0C6A} పరిచయం", [74_000]) == ["\u{0C67}:\u{0C67}\u{0C6A}"]) // Telugu
        #expect(linked("\u{0BE7}:\u{0BE7}\u{0BEA} அறிமுகம்", [74_000]) == ["\u{0BE7}:\u{0BE7}\u{0BEA}"]) // Tamil
    }

    @Test func aLetterOfAnyScriptTouchingTheTimestampMakesItPartOfAWord() {
        #expect(linked("1:14కి", [74_000]).isEmpty)
        #expect(linked("అ1:14", [74_000]).isEmpty)
    }

    @Test func rangesPointAtTheRightTextAfterEmojiAndCombiningCharacters() {
        let text = "🙏 e\u{0301} 0:00 Intro 👨‍👩‍👧 1:14 Reading"
        #expect(linked(text, [0, 74_000]) == ["0:00", "1:14"])
    }

    // MARK: - Link URLs

    @Test func theLinkURLRoundTripsTheTime() throws {
        let url = try #require(DescriptionTimestamps.url(forMilliseconds: 74_000))
        let zero = try #require(DescriptionTimestamps.url(forMilliseconds: 0))

        #expect(url.scheme == DescriptionTimestamps.scheme)
        #expect(DescriptionTimestamps.milliseconds(from: url) == 74_000)
        #expect(DescriptionTimestamps.milliseconds(from: zero) == 0)
    }

    @Test func otherURLsAreNotTimestampLinks() throws {
        let web = try #require(URL(string: "https://example.com/seek/5"))
        let badPath = try #require(URL(string: "\(DescriptionTimestamps.scheme)://seek/abc"))
        let negative = try #require(URL(string: "\(DescriptionTimestamps.scheme)://seek/-5"))
        let otherHost = try #require(URL(string: "\(DescriptionTimestamps.scheme)://other/5"))

        #expect(DescriptionTimestamps.milliseconds(from: web) == nil)
        #expect(DescriptionTimestamps.milliseconds(from: badPath) == nil)
        #expect(DescriptionTimestamps.milliseconds(from: negative) == nil)
        #expect(DescriptionTimestamps.milliseconds(from: otherHost) == nil)
    }
}
