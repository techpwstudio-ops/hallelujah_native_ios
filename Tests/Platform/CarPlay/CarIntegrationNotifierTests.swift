import Foundation
import Testing
@testable import Hallelujah

@MainActor
struct CarIntegrationNotifierTests {
    private final class Box: @unchecked Sendable {
        var changes: [CarIntegrationNotifier.Change] = []
        var playlistIDs: [String?] = []
    }

    @Test func eachCallPostsItsChange() {
        let box = Box()
        let token = NotificationCenter.default.addObserver(
            forName: CarIntegrationNotifier.didChange, object: nil, queue: nil
        ) { note in
            if let change = CarIntegrationNotifier.change(from: note) { box.changes.append(change) }
            box.playlistIDs.append(CarIntegrationNotifier.playlistID(from: note))
        }
        defer { NotificationCenter.default.removeObserver(token) }

        CarIntegrationNotifier.recentPlayed()
        CarIntegrationNotifier.favouritesChanged()
        CarIntegrationNotifier.downloadsChanged()
        CarIntegrationNotifier.playlistsChanged()
        CarIntegrationNotifier.playlistSongsChanged(playlistID: "p1")

        #expect(box.changes == [.recentPlayed, .favourites, .downloads, .playlists, .playlistSongs])
        #expect(box.playlistIDs.last == "p1")
    }

    @Test func emptyPlaylistIDIsIgnored() {
        let box = Box()
        let token = NotificationCenter.default.addObserver(
            forName: CarIntegrationNotifier.didChange, object: nil, queue: nil
        ) { note in
            if let change = CarIntegrationNotifier.change(from: note) { box.changes.append(change) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        CarIntegrationNotifier.playlistSongsChanged(playlistID: nil)
        CarIntegrationNotifier.playlistSongsChanged(playlistID: "")
        #expect(box.changes.isEmpty)
    }
}
