import UIKit

/// The dashboard tab each ad `screen` key opens (`kAdScreenTabs`,
/// `lib/ads/ad_screen.dart`). The keys are the backend's `COMPANY_AD_SCREENS`.
/// A key missing here is one an older app doesn't know — the ad then opens its
/// link instead.
enum AdScreenTab {
    static func tab(for item: Any?) -> AppTab? {
        switch item as? String {
        case "home": .home
        case "search": .search
        case "emet": .aiAssistant
        case "library": .library
        case "bible": .read
        default: nil
        }
    }
}

/// The link a `deeplink` action carries (`adDeepLinkUri`): http(s) and the
/// `/share/<code>` shape (two path segments); nil sends the tap to the
/// browser instead of nowhere.
func adDeepLinkURL(_ item: Any?) -> URL? {
    guard let string = (item as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let url = URL(string: string),
          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          url.pathComponents.filter({ $0 != "/" }).count == 2
    else { return nil }
    return url
}

let adShareableActionTypes: Set<String> = [
    "song", "creator", "playlist", "userPlaylist", "companyPlaylist", "verseOfDay",
]

/// `openAdAction` (`lib/ads/ad_action.dart`) — the one place that decides
/// in-app vs. browser, so every ad surface (home banner, rail, player ad
/// break, mini banner) behaves identically.
///
/// In-app destinations — `subscription`, a `deeplink` (our own share link),
/// a `screen` (a dashboard tab) or a `ShareableType` action carrying an `item`
/// — track a client-side click and open like the equivalent shared link.
/// Anything else (no action, an unrecognised type, a missing/invalid item, a
/// screen this build has no tab for) opens `clickUrl`, whose signed redirect
/// records the click server-side, so it is not tracked again here.
@MainActor
func openAdAction(_ ad: AdCreative, coordinator: AppNavigationCoordinator, adsRepository: AdsRepository) {
    if let action = ad.action {
        if action.type == "subscription" {
            adsRepository.trackClick(ad.impressionToken)
            coordinator.push(.subscriptionPlans)
            return
        }

        if action.type == "deeplink", let url = adDeepLinkURL(action.item) {
            adsRepository.trackClick(ad.impressionToken)
            DeepLinkService.shared.openAdLink(url, coordinator: coordinator)
            return
        }

        if action.type == "screen", let tab = AdScreenTab.tab(for: action.item) {
            adsRepository.trackClick(ad.impressionToken)
            // Closes the now-playing screen an ad break is shown over and
            // brings the shell to the front on that tab.
            coordinator.resetToRoot(selecting: tab)
            return
        }

        if let item = action.itemObject, adShareableActionTypes.contains(action.type) {
            adsRepository.trackClick(ad.impressionToken)
            DeepLinkService.shared.openShareable(shareableType: action.type, item: item, coordinator: coordinator)
            return
        }
    }

    if let clickUrl = ad.clickUrl, let url = URL(string: clickUrl) {
        UIApplication.shared.open(url)
    }
}
