import Foundation
import Testing
@testable import Hallelujah

@MainActor
struct QueueHandoffTests {
    @Test func candidateQueueDropsTheFinishedSongAndDuplicates() {
        let fetched = [Song.fixture(id: "a"), .fixture(id: "b"), .fixture(id: "a"), .fixture(id: "c"), .fixture(id: "b")]
        let result = QueueHandoffResolver.candidateQueue(fetched, after: "c")
        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test func candidateQueueCanBeEmpty() {
        #expect(QueueHandoffResolver.candidateQueue([.fixture(id: "x")], after: "x").isEmpty)
    }

    @Test func attributionMapsKindToPlayerType() {
        let playlist = RelatedItem(kind: .playlist, id: "p1", title: "Worship", reason: nil, image: nil, imageVariants: nil)
        let creator = RelatedItem(kind: .creator, id: "c1", title: "Show", reason: nil, image: nil, imageVariants: nil)
        #expect(QueueHandoffResolver.attribution(for: playlist) == QueueAttribution(playerType: .companyPlaylist, id: "p1", title: "Worship"))
        #expect(QueueHandoffResolver.attribution(for: creator) == QueueAttribution(playerType: .creator, id: "c1", title: "Show"))
    }

    @Test func boundedReturnsNilWhenOperationOutlastsTheLimit() async {
        let slow: Int? = await QueueHandoffResolver.bounded(.milliseconds(30)) {
            try? await Task.sleep(for: .seconds(5))
            return 1
        }
        #expect(slow == nil)
        let fast: Int? = await QueueHandoffResolver.bounded(.seconds(5)) { 7 }
        #expect(fast == 7)
    }

    @Test func historyIsBoundedToThree() {
        #expect(QueueHandoffResolver.maxHistory == 3)
    }
}
