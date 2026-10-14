import SwiftUI

/// The children of a horizontal rail with its ad slots woven in
/// (`layout.isAdAt` / `organicIndexAt` in the Dart rails): each organic item is
/// drawn by `organic` from its index into the rail's own data, each ad position
/// by `ad` from its slot id. With a layout that has no ads this is just the
/// rail's own items.
struct HomeAdRailItems<Organic: View, Ad: View>: View {
    let layout: RailAdLayout
    @ViewBuilder var organic: (Int) -> Organic
    @ViewBuilder var ad: (String) -> Ad

    var body: some View {
        ForEach(layout.items) { item in
            switch item {
            case .organic(let index): organic(index)
            case .ad(let slotId): ad(slotId)
            }
        }
    }
}

enum HomeRailAds {
    /// `_adRailId` (`home_section_builder.dart`): what a rail's square ads are
    /// filed under — the section's own id, unique per rail and per tab. Nil for
    /// a rail that carries none: "Continue Your Journey" (`recent_songs`, or a
    /// `recent-…` id) never gets an ad.
    static func adRailId(sectionId: String, viewType: String) -> String? {
        if sectionId.isEmpty { return nil }
        if viewType == "recent_songs" || sectionId.hasPrefix("recent-") { return nil }
        return sectionId
    }
}
