import SwiftUI

/// Ports `AdCompanionBanner` (`lib/widgets/player/ad_companion_banner.dart`):
/// the dismissible banner pinned to the bottom of the NORMAL (non-ad-break)
/// now-playing screen once a break ends, only when the creative's
/// `lingerAfterDismiss` was true (`AdPacingController.endAdBreak`). Renders
/// nothing otherwise.
///
/// 16 side / 12 bottom inset; a `#1C1C1E` radius-14 card with the 44pt companion
/// picture (radius 8), the advertiser's name (13 w600) over "Visit Site" (12,
/// white @ 54%), then the ad's ⋮ menu next to — not instead of — the close X.
/// A tap anywhere else opens the ad. The impression is counted once the card has
/// been on screen for the shared dwell time.
///
/// (`Ios26BottomSpacing` is not needed: the native full player is a full-screen
/// cover above the floating tab bar, so nothing is painted under the banner.)
struct AdCompanionBanner: View {
    let pacing: AdPacingController

    @Environment(AppNavigationCoordinator.self) private var coordinator
    private let ads: AdsRepository = DependencyContainer.current.resolve()

    var body: some View {
        if pacing.showCompanionBanner, let ad = pacing.companionAd, let art = ad.companionImageUrl {
            banner(ad: ad, art: art)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
        }
    }

    private func banner(ad: AdCreative, art: String) -> some View {
        let advertiser = ad.advertiserName ?? ""
        return AdImpressionTrigger(onVisible: { ads.trackImpressionOnce(ad.impressionToken) }) {
            HStack(spacing: 10) {
                ArtworkView(url: URL(string: art), width: 44, height: 44, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 0) {
                    if !advertiser.isEmpty {
                        Text(advertiser)
                            .font(.custom(Typography.fontFamily, size: 13, relativeTo: .footnote).weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                    Text("Visit Site")
                        .font(.custom(Typography.fontFamily, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.white.opacity(0.54))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The ⋮ next to the X, not instead of it: closing this banner is
                // a one-tap gesture people already know.
                AdOptionsButton(ad: ad, onDismissAd: {
                    pacing.dismissCompanion()
                    return true
                }, style: .plain, size: 18)

                Button { pacing.dismissCompanion() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(10)
            .glassRounded(14)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { pacing.openAction(for: ad, coordinator: coordinator) }
        }
        // One banner per ad: a new ad is a new impression.
        .id(ad.impressionToken)
    }
}
