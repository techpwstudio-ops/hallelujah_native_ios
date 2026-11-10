import Testing
@testable import Hallelujah

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

    // MARK: - Silent video (`hasVideo`, `videoFile`)

    @Test func hasVideoNeedsANonBlankKey() {
        #expect(!Song.fixture(videoFile: nil).hasVideo)
        #expect(!Song.fixture(videoFile: "").hasVideo)
        #expect(!Song.fixture(videoFile: "   \n\t").hasVideo)
        #expect(Song.fixture(videoFile: "ep/video-song/1-silent/original.mp4").hasVideo)
    }

    @Test func hasVideoIsNotGatedOnType() {
        // Flutter's `Song.hasVideo` looks at the column only.
        #expect(Song.fixture(type: "music", videoFile: "a.mp4").hasVideo)
        #expect(Song.fixture(type: "episode", videoFile: "a.mp4").hasVideo)
    }

    @Test func withFavoritedKeepsTheVideo() {
        let toggled = Song.fixture(videoFile: "a.mp4").withFavorited(true)
        #expect(toggled.videoFile == "a.mp4")
        #expect(toggled.hasVideo)
    }
}
