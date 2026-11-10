import Testing
@testable import Hallelujah

/// `Song.episodeTimeline` survives the helpers that rebuild a `Song`.
struct SongEpisodeTimelineTests {
    private let timeline = EpisodeTimeline(
        chapters: [
            EpisodeChapter(startMs: 0, endMs: 5000, title: "Intro"),
            EpisodeChapter(startMs: 5000, endMs: nil, title: "Main"),
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
