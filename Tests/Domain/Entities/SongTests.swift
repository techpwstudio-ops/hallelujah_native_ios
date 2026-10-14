import Testing
@testable import GHallelujah

struct SongTests {
    @Test func musicUsesSquareArtwork() {
        let song = Song.fixture(type: "music", image: "square.png", rectangleImage: "rect.png")
        #expect(!song.isEpisode)
        #expect(song.displayImage == "square.png")
        #expect(song.displayAspectRatio == 1.0)
    }

    @Test func episodeUsesRectangleArtwork() {
        let song = Song.fixture(type: "episode", image: "square.png", rectangleImage: "rect.png")
        #expect(song.isEpisode)
        #expect(song.displayImage == "rect.png")
        #expect(song.displayAspectRatio == 16.0 / 9.0)
    }

    @Test func unknownTypeDegradesToNotAnEpisode() {
        #expect(!Song.fixture(type: "podcast-v2").isEpisode)
        #expect(!Song.fixture(type: nil).isEpisode)
    }

    @Test func withFavoritedFlipsOnlyTheFlag() {
        let original = Song.fixture(id: "a", title: "Keep me", isFavorited: false)
        let toggled = original.withFavorited(true)

        #expect(toggled.isFavorited)
        #expect(!original.isFavorited)
        #expect(toggled.id == "a")
        #expect(toggled.title == "Keep me")
        #expect(toggled.withFavorited(false) == original)
    }
}
