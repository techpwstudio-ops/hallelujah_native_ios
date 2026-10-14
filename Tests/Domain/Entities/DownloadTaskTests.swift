import Foundation
import Testing
@testable import GHallelujah

struct DownloadTaskTests {
    private func task(state: DownloadState = .completed) -> DownloadTask {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return DownloadTask(
            songID: "s1", state: state, quality: .standard, bytesWritten: 100, totalBytes: 200,
            localFileName: "s1.m4a", createdAt: date, updatedAt: date, urlSessionTaskIdentifier: 7,
            songTitle: "Saved", songArtworkPath: "a.png", songArtworkVariants: "sm",
            songGenreName: "Gospel", songDurationSeconds: 180, songType: "music"
        )
    }

    @Test func catalogRoundTripsThroughJSON() throws {
        let tasks = [task(), task(state: .failed)]
        let data = try JSONEncoder().encode(tasks)
        #expect(try JSONDecoder().decode([DownloadTask].self, from: data) == tasks)
    }

    @Test func identityIsTheSongID() {
        #expect(task().id == "s1")
    }

    @Test func stateNamesAreStableOnDisk() throws {
        let data = try JSONEncoder().encode(task(state: .paused))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"paused\""))
    }
}
