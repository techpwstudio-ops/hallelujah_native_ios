import SwiftUI

/// Ports `AdBreakMiniBanner` (`lib/widgets/player/ad_break_mini_banner.dart`):
/// the strip that says an ad is still playing, sitting on top of the mini player
/// wherever the listener has wandered to.
///
/// The break's own screen (`AdBreakView`, shown inline by `FullPlayerView`) is a
/// presentation: dismiss it, or never open it because the break started while the
/// listener was on the home feed, and the break carries on with nothing on screen
/// to explain the voice they are hearing, and no way back to the advertiser. This
/// is that missing line. It lives in the dock, so it is only seen when the ad's
/// own screen is not up — while that screen is up it covers this.
///
/// A `#BA0319` radius-8 bar: the ad's picture as a 32pt thumbnail (when it has
/// one), the headline (13 w500, or the advertiser's name, or "Advertisement"), a
/// "More Info" pill when the ad has somewhere to go, and the ad's ⋮ menu, whose
/// "Close ad" respects the creative's skip lock (`dismissIfSkippable`). A tap
/// reopens the player. Renders nothing outside a break.
///
/// Not ported: the impression this strip counts in Flutter. The native break
/// confirms its impression when playback starts (`AdPacingController`), whether
/// or not any surface is up, so counting it here again would double it.
struct AdBreakMiniBanner: View {
    let pacing: AdPacingController
    var horizontalMargin: CGFloat = 0

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        if pacing.isAdBreak, let ad = pacing.currentAd {
            // The square, whichever the song is: it is a thumbnail, so the shape
            // that needs no cropping is the one to take.
            let art = adBreakArt(for: ad, isMusic: true)
            HStack(spacing: 0) {
                if let art {
                    ArtworkView(
                        url: URL(string: art.url),
                        width: 32,
                        height: 32,
                        cornerRadius: Dimens.cornerRadiusSmall
                    )
                    .padding(.trailing, Dimens.spacing8)
                }

                Text(Self.headline(for: ad))
                    .font(.custom(Typography.fontFamily, size: 13, relativeTo: .footnote).weight(.medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if ad.hasDestination {
                    Button { pacing.openAction(for: ad, coordinator: coordinator) } label: {
                        Text(ad.ctaLabel?.isEmpty == false ? (ad.ctaLabel ?? "More Info") : "More Info")
                            .font(.custom(Typography.fontFamily, size: 11, relativeTo: .caption2).weight(.semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }

                // Same menu, same corner as every other ad surface — this strip
                // is often the only ad UI on screen once the break's own screen
                // has been backed out of.
                AdOptionsButton(ad: ad, onDismissAd: { pacing.dismissIfSkippable() }, style: .plain, size: 18)
            }
            .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 2))
            .background(RoundedRectangle(cornerRadius: 8).fill(Self.red))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            // Back to the ad it is talking about — the same gesture the mini
            // player under it uses to reopen the song.
            .onTapGesture { coordinator.presentPlayer() }
            .padding(.horizontal, horizontalMargin)
        }
    }

    /// `ColorTheme.red` (0xFFBA0319).
    private static let red = Color(red: 186.0 / 255, green: 3.0 / 255, blue: 25.0 / 255)

    /// The advertiser's own line if they gave one; their name otherwise. Never
    /// blank — this strip is the only thing on screen naming what is playing.
    static func headline(for ad: AdCreative) -> String {
        if let headline = ad.headline, !headline.isEmpty { return headline }
        if let advertiser = ad.advertiserName, !advertiser.isEmpty { return advertiser }
        return "Advertisement"
    }
}
