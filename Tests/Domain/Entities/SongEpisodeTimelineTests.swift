import Testing
@testable import Hallelujah

/// `Song.episodeTimeline` survives the helpers that rebuild a `Song`.
struct SongEpisodeTimelineTests {
    private let timeline = EpisodeTimeline(
        chapters: [
            EpisodeChapter(id: "1", startMs: 0, endMs: 5000, title: "Intro", imageURL: nil, linkURL: nil),
            EpisodeChapter(id: "2", startMs: 5000, endMs: 9000, title: "Main", imageURL: nil, linkURL: nil),
        ],
        speakers: [],
        transcript: .absent
    )

    @Test func withFavoritedKeepsTheTimeline() {
        var song = Song.fixture(type: "episode")
        song.episodeTimeline = timeline

        #expect(song.withFavorited(true).episodeTimeline == timeline)
        #expect(song.withFavorited(true).isFavorited)
    }

    @Test func aSongWithoutEpisodeDataHasNoTimeline() {
        #expect(Song.fixture().episodeTimeline == nil)
    }
}
