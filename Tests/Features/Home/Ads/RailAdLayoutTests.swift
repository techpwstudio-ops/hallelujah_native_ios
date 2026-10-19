import Testing
@testable import Hallelujah

struct RailAdLayoutTests {
    @Test func noRailIdMeansNoAds() {
        let layout = RailAdLayout(organicCount: 10, railId: nil, interval: 4)
        #expect(!layout.hasAds)
        #expect(layout.itemCount == 10)
        #expect(layout.items.allSatisfy { if case .organic = $0 { true } else { false } })
    }

    @Test func railNotLongerThanOneBlockHasNoAds() {
        #expect(!RailAdLayout(organicCount: 4, railId: "r", interval: 4).hasAds)
        #expect(RailAdLayout(organicCount: 5, railId: "r", interval: 4).hasAds)
    }

    @Test func zeroIntervalMeansNoAds() {
        #expect(!RailAdLayout(organicCount: 9, railId: "r", interval: 0).hasAds)
    }

    @Test func adSitsBetweenBlocksNeverFirstOrLast() {
        // a b c d [AD] e f g h [AD] i
        let layout = RailAdLayout(organicCount: 9, railId: "r", interval: 4)
        #expect(layout.itemCount == 11)
        #expect(layout.isAdAt(4))
        #expect(layout.isAdAt(9))
        #expect(!layout.isAdAt(0))
        #expect(!layout.isAdAt(10))
    }

    @Test func noTrailingAdWhenRailEndsOnABlockBoundary() {
        let layout = RailAdLayout(organicCount: 8, railId: "r", interval: 4)
        #expect(layout.itemCount == 9)
        #expect(!layout.isAdAt(8))
    }

    @Test func organicIndexSkipsTheAds() {
        let layout = RailAdLayout(organicCount: 9, railId: "r", interval: 4)
        let organic = (0..<layout.itemCount).filter { !layout.isAdAt($0) }.map(layout.organicIndexAt)
        #expect(organic == Array(0..<9))
    }

    @Test func slotIdsNameThePositionOfTheAd() {
        let layout = RailAdLayout(organicCount: 9, railId: "rail-x", interval: 4)
        #expect(layout.slotIdAt(4) == "rail-x#0")
        #expect(layout.slotIdAt(9) == "rail-x#1")
    }

    @Test func itemsListMatchesIndexMaths() {
        let layout = RailAdLayout(organicCount: 5, railId: "r", interval: 2)
        #expect(layout.items == [
            .organic(0), .organic(1), .ad(slotId: "r#0"),
            .organic(2), .organic(3), .ad(slotId: "r#1"),
            .organic(4),
        ])
    }
}
