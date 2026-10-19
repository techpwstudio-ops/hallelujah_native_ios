import Foundation
import Testing
@testable import Hallelujah

struct RecentlyPlayedSyncerTests {
    @Test func endpointPostsToSongRecent() {
        let endpoint = RecentlyPlayedSyncer.endpoint(songID: "s1")
        #expect(endpoint.path == "/song/s1/recent")
        #expect(endpoint.method == .post)
    }

    @Test func bodyOmitsAbsentKeysAndEmptySearchQuery() {
        let payload = RecentlyPlayedSyncer.Payload(
            songID: "s1", sessionID: "sess", playSource: nil, sourceID: nil, sourceRank: nil, searchQuery: ""
        )
        let map = RecentlyPlayedSyncer.bodyDictionary(for: payload)
        #expect(map.keys.sorted() == ["sessionId"])
    }

    @Test func bodyCarriesAttribution() {
        let payload = RecentlyPlayedSyncer.Payload(
            songID: "s1", sessionID: "sess", playSource: "album", sourceID: "al1", sourceRank: 3, searchQuery: "grace"
        )
        let map = RecentlyPlayedSyncer.bodyDictionary(for: payload)
        #expect(map["source"] as? String == "album")
        #expect(map["sourceId"] as? String == "al1")
        #expect(map["sourceRank"] as? Int == 3)
        #expect(map["searchQuery"] as? String == "grace")
    }

    @Test func sourceIDIgnoresEmptyAndNullStrings() {
        #expect(RecentlyPlayedSyncer.sourceID(from: nil) == nil)
        #expect(RecentlyPlayedSyncer.sourceID(from: "") == nil)
        #expect(RecentlyPlayedSyncer.sourceID(from: "null") == nil)
        #expect(RecentlyPlayedSyncer.sourceID(from: "abc") == "abc")
    }
}
