import UIKit

/// `openAdAction` (`lib/ads/ad_action.dart`) for a tapped ad card on a feed
/// surface — the same rule `AdPacingController.openAction` applies to the audio
/// ad break's CTA, for a creative that is not the player's current ad. An
/// in-app destination (`subscription`, or a `ShareableType` action carrying an
/// `item`) opens like a shared link to that content and tracks a client-side
/// click; anything else opens `clickUrl`, whose signed redirect records the
/// click server-side (so it is not tracked again here).
@MainActor
func openAdAction(_ ad: AdCreative, coordinator: AppNavigationCoordinator, adsRepository: AdsRepository) {
    let shareableActionTypes: Set<String> = [
        "song", "creator", "playlist", "userPlaylist", "companyPlaylist", "verseOfDay",
    ]

    if let action = ad.action {
        if action.type == "subscription" {
            adsRepository.trackClick(ad.impressionToken)
            coordinator.push(.subscriptionPlans)
            return
        }
        if let item = action.item, shareableActionTypes.contains(action.type) {
            adsRepository.trackClick(ad.impressionToken)
            DeepLinkService.shared.openShareable(shareableType: action.type, item: item, coordinator: coordinator)
            return
        }
    }

    if let clickUrl = ad.clickUrl, let url = URL(string: clickUrl) {
        UIApplication.shared.open(url)
    }
}
