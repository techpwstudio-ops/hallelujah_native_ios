import Foundation
import Testing
@testable import Hallelujah

struct CarPlayModelsTests {
    private let source = QueueAttribution(playerType: .home, id: nil, title: "")

    private func row(_ kind: CarPlayRow.Kind) -> CarPlayRow {
        CarPlayRow(id: "r", title: "T", subtitle: nil, artworkURL: nil, kind: kind)
    }

    @Test func onlyCreatorArtworkIsCircular() {
        #expect(row(.creator(id: "c")).isCircularArtwork)
        #expect(!row(.song(index: 0)).isCircularArtwork)
        #expect(!row(.companyPlaylist(id: "p")).isCircularArtwork)
        #expect(!row(.genre(id: "g")).isCircularArtwork)
    }

    @Test func trendingRailIsDetectedByViewTypeNotTitle() {
        let group = CarPlayRowGroup.empty(source: source)
        #expect(CarPlayRail(id: "1", title: "Anything", viewType: "trending", group: group).isTrendingGrid)
        #expect(!CarPlayRail(id: "2", title: "Trending", viewType: "songs", group: group).isTrendingGrid)
    }

    @Test func emptyGroupHasNoRowsOrSongs() {
        let group = CarPlayRowGroup.empty(source: source)
        #expect(group.rows.isEmpty)
        #expect(group.songs.isEmpty)
        #expect(group.source == source)
    }

    @Test func downloadedSnapshotCarriesDisplayFieldsFromTheTask() {
        let now = Date()
        let task = DownloadTask(
            songID: "s1", state: .completed, quality: .high, bytesWritten: 10, totalBytes: 10,
            localFileName: "s1.m4a", createdAt: now, updatedAt: now, urlSessionTaskIdentifier: nil,
            songTitle: "Saved", songArtworkPath: "art.png", songArtworkVariants: "sm",
            songGenreName: "Gospel", songDurationSeconds: 200, songType: "music"
        )
        let song = Song.makeDownloadedSnapshot(task)

        #expect(song.id == "s1")
        #expect(song.title == "Saved")
        #expect(song.displayImage == "art.png")
        #expect(song.duration == 200)
        #expect(song.audioUrls.isEmpty)
        #expect(!song.isFavorited)
    }
}
