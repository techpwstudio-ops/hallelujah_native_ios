import SwiftUI

/// Ports `MiniPlayerAdSlot` (`lib/widgets/player/mini_player_ad_slot.dart`):
/// everything that advertises on top of the mini player, in one place for the
/// dock.
///
/// Two things can be there, never both at once: the strip for an audio ad break
/// that is running, and the strip for the player's image ad. The image ad stands
/// down for the whole of a break (`PlayerAdController.setHeldOff`), so stacking
/// them costs nothing and leaves each to decide whether it has anything to say.
struct MiniPlayerAdSlot: View {
    let pacing: AdPacingController
    let playerAd: PlayerAdController

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 0) {
            AdBreakMiniBanner(pacing: pacing)
            PlayerAdStrip(
                controller: playerAd,
                // The full player is presented over the dock: the cover is the
                // surface then, not this strip.
                isUncovered: coordinator.presentedFullScreen == nil,
                onOpen: { ad in pacing.openAction(for: ad, coordinator: coordinator) }
            )
        }
    }
}
