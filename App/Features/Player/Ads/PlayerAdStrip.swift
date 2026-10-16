import SwiftUI

/// Ports `PlayerAdStrip` (`lib/widgets/player/player_ad_strip.dart`): the
/// player's image ad as the strip that rides on top of the mini player.
///
/// The full player covers its artwork with the ad; most of the time, though, the
/// listener is somewhere else with the mini player at the bottom of the screen.
/// This is the same ad — the one `PlayerAdController` has up, on the same clock —
/// in the shape that fits there: the ad's picture as a 48pt thumbnail, who it is
/// from, and a button that takes the listener to it. Opening the player moves the
/// ad onto the cover mid-showing and does not start another, so it is not counted
/// twice (`AdsRepository.trackImpressionOnce`).
///
/// ONLY WHERE THE MINI PLAYER IS. The dock builds this alongside the mini player
/// and nowhere else, so being in the tree is what tells the controller there is a
/// surface for the ad: its clock runs while this is mounted (and the full player
/// is not covering it), and stops when the mini player is hidden.
///
/// Renders nothing while the song's own cover is showing.
struct PlayerAdStrip: View {
    let controller: PlayerAdController
    /// False while the full player is presented over the dock.
    var isUncovered: Bool = true
    let onOpen: (AdCreative) -> Void
    var onImpression: ((AdCreative) -> Void)?

    var body: some View {
        let ad = controller.ad
        VStack(spacing: 0) {
            if let ad, ad.assetUrl != nil {
                PlayerAdStripCard(
                    ad: ad,
                    onDismissAd: {
                        controller.dismiss()
                        return true
                    },
                    onOpen: onOpen,
                    onImpression: onImpression
                )
                // One strip per ad: a new ad is a new impression.
                .id(ad.impressionToken)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        // `AnimatedSize` 250 ms.
        .animation(.easeInOut(duration: 0.25), value: ad?.impressionToken)
        .environment(\.adOptionsPresentationChanged) { controller.setOptionsOpen($0) }
        .playerAdSurface(controller, isEnabled: isUncovered)
    }
}

private struct PlayerAdStripCard: View {
    let ad: AdCreative
    let onDismissAd: () -> Bool
    let onOpen: (AdCreative) -> Void
    var onImpression: ((AdCreative) -> Void)?

    /// The same size as a row in a list of songs, so the strip reads as a row of
    /// the mini player's own.
    private static let thumbnailSize = Dimens.listItemThumbnailSizeSm
    /// The button never takes more than this of the strip.
    private static let buttonMaxWidth: CGFloat = 120
    /// `ColorTheme.darkFillColor` (0xFF282828).
    private static let fill = Color(red: 40.0 / 255, green: 40.0 / 255, blue: 40.0 / 255)

    var body: some View {
        let caption = AdCaption(ad: ad)
        HStack(spacing: 0) {
            AdImpressionTrigger(onVisible: {
                if let onImpression { onImpression(ad) } else { Self.countImpression(ad) }
            }) {
                ArtworkView(
                    url: ad.assetUrl.flatMap(URL.init(string:)),
                    width: Self.thumbnailSize,
                    height: Self.thumbnailSize,
                    cornerRadius: Dimens.cornerRadiusSmall
                )
            }

            VStack(alignment: .leading, spacing: Dimens.spacing2) {
                if !caption.title.isEmpty {
                    Text(caption.title)
                        .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body).weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                HStack(spacing: Dimens.spacing6) {
                    AdSponsoredBadge()
                    if !caption.subtitle.isEmpty {
                        Text(caption.subtitle)
                            .typography(Typography.bodySmall)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Dimens.spacing12)

            if ad.hasDestination {
                Button { onOpen(ad) } label: {
                    Text(ad.playerCTALabel)
                        .typography(Typography.labelLarge)
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .padding(.horizontal, Dimens.spacing12)
                        .padding(.vertical, Dimens.spacing6)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: Self.buttonMaxWidth)
                .padding(.leading, Dimens.spacing8)
            }

            // Hosted by the app shell: opening any sheet hides the dock this
            // strip is part of, and a sheet owned by this button would go with it.
            AdOptionsButton(ad: ad, onDismissAd: onDismissAd, style: .plain, usesSharedHost: true)
        }
        .padding(EdgeInsets(
            top: Dimens.spacing8,
            leading: Dimens.spacing8,
            bottom: Dimens.spacing8,
            trailing: Dimens.spacing2
        ))
        .glassRounded(Dimens.cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: Dimens.cornerRadius))
        .onTapGesture {
            if ad.hasDestination { onOpen(ad) }
        }
    }

    @MainActor
    private static func countImpression(_ ad: AdCreative) {
        let ads: AdsRepository = DependencyContainer.current.resolve()
        ads.trackImpressionOnce(ad.impressionToken)
    }
}
