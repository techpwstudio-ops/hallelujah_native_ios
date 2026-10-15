import Foundation
import Testing
@testable import GHallelujah

@MainActor
struct RelatedContentTests {
    @Test func reasonLabelsFollowKind() {
        func item(_ kind: RelatedItemKind, _ reason: String?) -> RelatedItem {
            RelatedItem(kind: kind, id: "1", title: "t", reason: reason, image: nil, imageVariants: nil)
        }
        #expect(item(.playlist, "same_genre").reasonLabel == "Similar sound")
        #expect(item(.creator, "same_genre").reasonLabel == "Similar shows")
        #expect(item(.creator, "popular").reasonLabel == "Popular show")
        #expect(item(.playlist, "new_signal").reasonLabel == "More like this")
    }

    @Test func decodesEnvelopeAndKind() throws {
        let json = #"{"data":{"kind":"creator","items":[{"id":5,"name":"Show","reason":"popular"}]}}"#
        let content = try JSONDecoder().decode(RelatedContentResponseDTO.self, from: Data(json.utf8)).toDomain()
        #expect(content.kind == .creator)
        #expect(content.items.map(\.id) == ["5"])
        #expect(content.items.first?.title == "Show")
    }

    @Test func missingDataIsEmpty() throws {
        let content = try JSONDecoder().decode(RelatedContentResponseDTO.self, from: Data("{}".utf8)).toDomain()
        #expect(content.isEmpty)
    }

    @Test func endpointEncodesExcludeId() {
        #expect(Endpoint.relatedContent(songId: "s", excludeId: nil, limit: 10).path == "/song/s/related?limit=10")
        #expect(Endpoint.relatedContent(songId: "s", excludeId: "a b", limit: 5).path == "/song/s/related?limit=5&excludeId=a%20b")
    }

    @Test func progressKeyOnlyForTrackedContainers() {
        func item(_ type: String, _ entity: String?) -> RecentContentItem {
            RecentContentItem(id: "i", itemType: type, entityId: entity, title: nil, subtitle: nil, image: nil,
                              imageVariants: nil, playedAt: nil, songId: nil, contentType: nil)
        }
        #expect(HomeRecentProgressBar.progressKey(for: item("album", "9")) == "album:9")
        #expect(HomeRecentProgressBar.progressKey(for: item("creator", "9")) == nil)
        #expect(HomeRecentProgressBar.progressKey(for: item("song", "9")) == nil)
        #expect(HomeRecentProgressBar.progressKey(for: item("album", nil)) == nil)
    }
}
