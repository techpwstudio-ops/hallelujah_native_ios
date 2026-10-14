import Foundation

/// Where the square ads go in a horizontal home rail — pure index maths
/// (`lib/ads/rail_ad_layout.dart`). An ad sits BETWEEN two organic items,
/// after every `interval` of them:
///
///     interval 4:   a b c d [AD] e f g h [AD] i
///
/// Never first, and never last. A rail that uses this builds `itemCount`
/// children, asks `isAdAt` of each, and maps the rest back to its own data
/// through `organicIndexAt`.
struct RailAdLayout: Equatable, Sendable {
    /// Items the rail has of its own, before any ad.
    let organicCount: Int
    /// Which rail this is — with the slot's position, the key a served ad is
    /// remembered under. Nil for a rail that carries no ads.
    var railId: String?
    /// Organic items between two ads. Zero for a rail that carries no ads.
    var interval = 0

    /// False when there is no `railId`, or the rail is not longer than one
    /// block of `interval` items — an ad needs an organic item on both sides.
    var hasAds: Bool { railId != nil && interval > 0 && organicCount > interval }

    /// Children the rail's list builds: its own items plus the ads between them.
    var itemCount: Int {
        hasAds ? organicCount + (organicCount - 1) / interval : organicCount
    }

    func isAdAt(_ index: Int) -> Bool {
        hasAds && index % (interval + 1) == interval
    }

    /// Which of the rail's own items the child at `index` shows. Only
    /// meaningful where `isAdAt` is false.
    func organicIndexAt(_ index: Int) -> Int {
        hasAds ? index - index / (interval + 1) : index
    }

    /// Identity of the ad slot at `index`: the rail plus which ad of the rail
    /// it is. Names the slot's POSITION, not the creative filling it.
    func slotIdAt(_ index: Int) -> String {
        "\(railId ?? "")#\(index / (interval + 1))"
    }

    /// One child of a rail's list, in order.
    enum Item: Equatable, Sendable {
        case organic(Int)
        case ad(slotId: String)
    }

    /// Every child of the rail's list, ad slots included, in display order.
    var items: [Item] {
        (0..<itemCount).map { index in
            isAdAt(index) ? .ad(slotId: slotIdAt(index)) : .organic(organicIndexAt(index))
        }
    }
}

extension RailAdLayout.Item: Identifiable {
    var id: String {
        switch self {
        case .organic(let index): "o\(index)"
        case .ad(let slotId): slotId
        }
    }
}
