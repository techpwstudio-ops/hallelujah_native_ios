import SwiftUI

/// Ports `PlayerAdCard` (`lib/widgets/player/player_ad_card.dart`): the ad that
/// covers the audio player's artwork while the image takeover has one up.
///
/// Fills whatever box it is given, which is the cover's own: a square over a
/// song's artwork, 16:9 over an episode's. The creative is drawn full-bleed with
/// the ad's chrome on it: the "Sponsored" chip (top left) and the ⋮ menu (top
/// right), and along the bottom, on a scrim, who the ad is from and a button that
/// takes the listener to it (max 45% of the width).
///
/// THE CARD DOES NOT BLOCK SWIPES. Swiping the cover is how a listener changes
/// song, and the pager that does it sits underneath. So every layer that is only
/// there to be looked at is non-hit-testable and the only things that take hits
/// are the two small buttons; the tap that opens the ad is attached by
/// `PlayerAdOverlay` to the pager itself (a simultaneous gesture).
struct PlayerAdCard: View {
    let ad: AdCreative
    /// The ⋮ menu's "close this ad". True when the ad really did go away, which
    /// it always does here.
    let onDismissAd: () -> Bool
    let onOpen: (AdCreative) -> Void
    var onImpression: ((AdCreative) -> Void)?

    private static let buttonMaxWidthFraction: CGFloat = 0.45
    private static let inset = Dimens.spacing12

    var body: some View {
        if let url = ad.assetUrl.flatMap(URL.init(string:)) {
            let caption = AdCaption(ad: ad)
            AdImpressionTrigger(onVisible: {
                if let onImpression { onImpression(ad) } else { Self.countImpression(ad) }
            }) {
                GeometryReader { proxy in
                    ZStack {
                        ArtworkView(url: url, width: proxy.size.width, height: proxy.size.height, cornerRadius: 0)
                            .background(PlayerStyle.fill)
                            .allowsHitTesting(false)

                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0x0D / 255), location: 0),
                                .init(color: Color.black.opacity(0x33 / 255), location: 0.45),
                                .init(color: Color.black.opacity(0xBF / 255), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)

                        AdSponsoredBadge()
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(Self.inset)

                        AdOptionsButton(ad: ad, onDismissAd: onDismissAd)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(Self.inset)

                        HStack(alignment: .bottom, spacing: 0) {
                            AdCardCaption(caption: caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                            if ad.hasDestination {
                                Button { onOpen(ad) } label: {
                                    Text(ad.playerCTALabel)
                                        .typography(Typography.titleSmall)
                                        .foregroundStyle(Color.black)
                                        .lineLimit(1)
                                        .padding(.horizontal, Dimens.spacing16)
                                        .padding(.vertical, Dimens.spacing12)
                                        .background(Capsule().fill(Color.white))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: proxy.size.width * Self.buttonMaxWidthFraction)
                                .padding(.leading, Dimens.spacing12)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(Self.inset)
                    }
                }
            }
            // A different creative is a different impression, even in a view
            // that lived on from the last one.
            .id(ad.impressionToken)
        }
    }

    @MainActor
    private static func countImpression(_ ad: AdCreative) {
        let ads: AdsRepository = DependencyContainer.current.resolve()
        ads.trackImpressionOnce(ad.impressionToken)
    }
}

/// The headline over the advertiser's name. Either may be absent.
private struct AdCardCaption: View {
    let caption: AdCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !caption.title.isEmpty {
                Text(caption.title)
                    // The song title's own style on the player, so the line that
                    // names what is on the cover keeps its weight when an ad is.
                    .typography(PlayerStyle.titleMediumBold)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
            }
            if !caption.subtitle.isEmpty {
                Text(caption.subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}
