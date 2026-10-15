import SwiftUI

/// Ports `PlayerAdOverlay` (`lib/widgets/player/player_ad_overlay.dart`): lays
/// the audio player's ad takeover over its artwork.
///
/// For every song that takes part, the cover stands alone for a few seconds, then
/// an ad covers it for half a minute, then the cover comes back, then an ad
/// again — until the song changes. `PlayerAdController` decides all of that; this
/// view only turns its answer into pixels on the full player, and tells it that
/// someone is looking (`playerAdSurface`).
///
/// ONE AD, TWO PLACES. The mini player's strip draws the very same ad while the
/// listener is elsewhere, and this picks it up when they open the player —
/// mid-ad, with its clock undisturbed. Opening the player does not start another.
///
/// ONLY THE COVER IS COVERED. The card fills exactly the content's box, and lets
/// drags through to the pager underneath, whose first horizontal movement is what
/// sends the ad away. A tap on the cover opens the ad.
struct PlayerAdOverlay<Content: View>: View {
    let controller: PlayerAdController
    /// `coordinator`-bound opener for the ad link handler.
    let onOpen: (AdCreative) -> Void
    /// Whether this page is the one on top (nothing — the queue, a menu —
    /// covers it); the clock waits while it is not.
    var isUncovered: Bool = true
    var onImpression: ((AdCreative) -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let ad = controller.ad
        // The gestures go on the cover itself, BEFORE the overlay is added, so
        // the card's own buttons are not under them (a simultaneous tap would
        // otherwise also open the ad when the ⋮ menu is pressed).
        content()
            .simultaneousGesture(
                TapGesture().onEnded {
                    if let ad = controller.ad, ad.hasDestination { onOpen(ad) }
                }
            )
            .simultaneousGesture(
                // A finger dragging along the cover is how the listener changes
                // song: that sends the ad away (`ScrollStartNotification` with a
                // horizontal drag). Programmatic page changes are not drags.
                DragGesture(minimumDistance: 8).onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        controller.dismiss()
                    }
                }
            )
            .overlay {
                // Fades in over the cover, and out again (350 ms).
                ZStack {
                    if let ad {
                        PlayerAdCard(
                            ad: ad,
                            onDismissAd: dismissAd,
                            onOpen: onOpen,
                            onImpression: onImpression
                        )
                        .id(ad.impressionToken)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: ad?.impressionToken)
            }
            .environment(\.adOptionsPresentationChanged) { controller.setOptionsOpen($0) }
            .playerAdSurface(controller, isEnabled: isUncovered)
    }

    /// The ⋮ menu's "close this ad".
    private func dismissAd() -> Bool {
        controller.dismiss()
        return true
    }
}
