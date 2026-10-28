import Foundation
import Testing
@testable import Hallelujah

struct RecentSongSnapshotTests {
    @Test func snapshotKeepsTheFieldsASearchHistoryRowNeeds() {
        let song = Song.fixture(
            id: "s1", title: "Amazing Grace", type: "music", image: "sq.png", imageVariants: "sm,md",
            rectangleImage: "re.png", primaryArtists: "Choir", featuredArtists: "Soloist"
        )
        let snapshot = RecentSongSnapshot(song: song)

        #expect(snapshot.id == "s1")
        #expect(snapshot.title == "Amazing Grace")
        #expect(snapshot.image == "sq.png")
        #expect(snapshot.imageVariants == "sm,md")
        #expect(snapshot.primaryArtists == "Choir")
        #expect(snapshot.featuredArtists == "Soloist")
    }

    @Test func rebuiltSongIsPlayableShapedButCarriesNoAudioUrls() {
        let rebuilt = RecentSongSnapshot(song: .fixture(id: "s2", title: "Hymn")).asSong
        #expect(rebuilt.id == "s2")
        #expect(rebuilt.title == "Hymn")
        #expect(rebuilt.audioUrls.isEmpty)
        #expect(!rebuilt.isFavorited)
    }

    @Test func snapshotSurvivesAJSONRoundTrip() throws {
        let snapshot = RecentSongSnapshot(song: .fixture(id: "s3"))
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(RecentSongSnapshot.self, from: data) == snapshot)
    }
}
