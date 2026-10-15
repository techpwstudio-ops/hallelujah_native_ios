import SwiftUI
import Observation

/// One home-feed ad banner spot (`_AdBannerSpot`, `home_v2_feed_sliver.dart`):
/// which backend placement fills it, the aspect ratio its creative is shaped to
/// (must match that placement's `acceptedAssetTypes` spec on the backend, or the
/// image gets letterboxed), whether it draws the advertiser-details card, and —
/// for a details-card spot only — the plain-banner placement/ratio to fall back
/// to when a creative has no avatar to put in that card.
struct HomeAdBannerSpot: Equatable, Sendable {
    let placementKey: String
    let aspectRatio: CGFloat
    let showAdvertiserDetails: Bool
    var fallbackPlacementKey: String?
    var fallbackAspectRatio: CGFloat?

    /// `Dimens.homeAdBannerAspectRatio` (4 / 1).
    static let bannerAspectRatio: CGFloat = 4 / 1
    /// `Dimens.homeAdBannerSecondaryAspectRatio` (16 / 9).
    static let secondaryAspectRatio: CGFloat = 16 / 9

    /// `_kHomeAdBannerSpots`: `{ anchor rail key: spot }`. A banner renders
    /// immediately after its anchor rail.
    static let spotsByAnchorKey: [String: HomeAdBannerSpot] = [
        "newReleasesMusic": HomeAdBannerSpot(
            placementKey: "image_banner_wide",
            aspectRatio: bannerAspectRatio,
            showAdvertiserDetails: false
        ),
        "creators": HomeAdBannerSpot(
            placementKey: "image_wide_16_9",
            aspectRatio: secondaryAspectRatio,
            showAdvertiserDetails: true,
            fallbackPlacementKey: "image_banner_wide",
            fallbackAspectRatio: bannerAspectRatio
        ),
    ]

    static func spot(forAnchorKey key: String) -> HomeAdBannerSpot? {
        spotsByAnchorKey[key]
    }
}

/// Fetches one banner ad, applying the details-card fallback rule, and settles
/// on nothing for a no-fill, a failure, or artwork that will not load.
@MainActor
@Observable
final class HomeAdBannerViewModel {
    /// What actually got rendered, which can differ from the spot when the
    /// details-card format had to fall back to a plain banner.
    struct Resolved {
        let ad: AdCreative
        let showsAdvertiserDetails: Bool
        let aspectRatio: CGFloat
    }

    private(set) var resolved: Resolved?
    private(set) var isDismissed = false

    @ObservationIgnored private let serve: (String) async -> AdCreative?
    @ObservationIgnored private let prepare: (AdCreative) async -> Bool
    @ObservationIgnored private var didLoad = false

    init(
        serve: @escaping (String) async -> AdCreative? = { placement in
            let ads: AdsRepository = DependencyContainer.current.resolve()
            return await ads.serveThroughGate(placement: placement)
        },
        prepare: @escaping (AdCreative) async -> Bool = { await AdArtwork.warm($0) }
    ) {
        self.serve = serve
        self.prepare = prepare
    }

    var visible: Resolved? { isDismissed ? nil : resolved }

    func load(spot: HomeAdBannerSpot) async {
        guard !didLoad else { return }
        didLoad = true

        var ad = await serve(spot.placementKey)
        var showsDetails = spot.showAdvertiserDetails
        var aspectRatio = spot.aspectRatio

        // The details row's leading avatar has nothing to draw from this
        // creative — fall back to the plain-banner placement/layout rather
        // than a card with an empty slot where the avatar belongs.
        if showsDetails,
           let first = ad,
           first.advertiserLogoUrl == nil,
           first.squareImageUrl == nil,
           let fallbackKey = spot.fallbackPlacementKey,
           let fallbackRatio = spot.fallbackAspectRatio
        {
            ad = await serve(fallbackKey)
            showsDetails = false
            aspectRatio = fallbackRatio
        }

        // The slot only opens with a picture in it: artwork that cannot load
        // makes the ad no ad at all.
        if let candidate = ad {
            let loaded = candidate.assetUrl != nil ? await prepare(candidate) : false
            if !loaded { ad = nil }
        }

        guard !Task.isCancelled else { didLoad = false; return }
        resolved = ad.map { Resolved(ad: $0, showsAdvertiserDetails: showsDetails, aspectRatio: aspectRatio) }
    }

    /// The ⋮ menu's "close this ad": the slot collapses exactly as on a no-fill.
    func dismiss() -> Bool {
        isDismissed = true
        return true
    }
}

/// `HomeAdBannerSlot` (`lib/widgets/home/home_ad_banner_slot.dart`): fetches its
/// own ad on mount and renders nothing while loading or on a no-fill/error —
/// so a frequency-capped or no-inventory placement leaves no gap.
@MainActor
struct HomeAdBannerSlot: View {
    let spot: HomeAdBannerSpot

    @State private var model = HomeAdBannerViewModel()
    @State private var adsRepository: AdsRepository = DependencyContainer.current.resolve()
    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        Group {
            if let resolved = model.visible {
                banner(resolved)
            } else {
                // Not EmptyView: the load task must have a view to hang on.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task { await model.load(spot: spot) }
    }

    private func banner(_ resolved: HomeAdBannerViewModel.Resolved) -> some View {
        let ad = resolved.ad
        return Group {
            if resolved.showsAdvertiserDetails {
                HomeAdDetailsCard(ad: ad, aspectRatio: resolved.aspectRatio, onDismissAd: { model.dismiss() })
            } else {
                plainBanner(ad, aspectRatio: resolved.aspectRatio)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openAdAction(ad, coordinator: coordinator, adsRepository: adsRepository)
        }
        .padding(.horizontal, Dimens.sectionPaddingH)
        .frame(maxWidth: .infinity)
        .modifier(BannerImpression(ad: ad) {
            adsRepository.trackImpression(ad.impressionToken)
        })
    }

    private func plainBanner(_ ad: AdCreative, aspectRatio: CGFloat) -> some View {
        ZStack {
            // The advertiser's own design edge-to-edge: cropping any of it away
            // isn't ours to do.
            AdRemoteImage(urlString: ad.assetUrl ?? "", contentMode: .fit, placeholder: .clear)
            AdSponsoredBadge()
                .padding(Dimens.spacing8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Opposite corner to the badge: the two together read as "this is
            // an ad, and here is what you can do about it".
            AdOptionsButton(ad: ad, onDismissAd: { model.dismiss() }, size: 16, overlaySize: 24, usesSharedHost: true)
                .padding(Dimens.spacing8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous))
    }
}

private struct BannerImpression: ViewModifier {
    let ad: AdCreative
    let onVisible: () -> Void

    func body(content: Content) -> some View {
        AdImpressionTrigger(onVisible: onVisible) { content }
            .id(ad.impressionToken)
    }
}

/// The `image_wide_16_9` layout (`_AdDetailsCard`): a clean thumbnail on top,
/// then a feed-ad-style list tile — advertiser logo, headline, "Sponsored ·
/// advertiser" subtitle and the ⋮ menu. Card chrome and spacing mirror
/// `HomeListItemUi` (the podcast episode card): same `screenPaddingAll` inset,
/// same `userThumbnailSize` avatar.
private struct HomeAdDetailsCard: View {
    let ad: AdCreative
    let aspectRatio: CGFloat
    let onDismissAd: () -> Bool

    var body: some View {
        // A same-campaign `image_square` creative stands in when the advertiser
        // never uploaded a dedicated logo.
        let logo = ad.advertiserLogoUrl ?? ad.squareImageUrl
        let advertiserName = ad.advertiserName ?? ""
        let headline = (ad.headline?.isEmpty == false) ? ad.headline! : String(localized: "Advertisement")
        let subtitle = advertiserName.isEmpty ? String(localized: "Sponsored") : String(localized: "Sponsored \u{00B7} \(advertiserName)")
        let bodyText = ad.bodyText ?? ""

        VStack(alignment: .leading, spacing: 0) {
            // Media stays clean — no badge, no ⋮ on top of it; both live in the
            // tile below, on the card's own background.
            AdRemoteImage(urlString: ad.assetUrl ?? "", contentMode: .fill)
                .aspectRatio(aspectRatio, contentMode: .fit)
            Color.clear.frame(height: Dimens.verticalSpacing)
            HStack(alignment: .center, spacing: 0) {
                if let logo {
                    AdRemoteImage(urlString: logo, contentMode: .fill)
                        .frame(width: Dimens.userThumbnailSize, height: Dimens.userThumbnailSize)
                        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .continuous))
                    Color.clear.frame(width: Dimens.leadingSpacing)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(headline)
                        .typography(Typography.titleSmall)
                        .tracking(0.2)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Color.clear.frame(height: 4)
                    Text(subtitle)
                        .font(.custom(Typography.fontFamily, size: 12, relativeTo: .caption).weight(.regular))
                        .foregroundStyle(HomeColors.white70)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: Dimens.spacing8)
                AdOptionsButton(ad: ad, onDismissAd: onDismissAd, style: .plain, usesSharedHost: true)
            }
            if !bodyText.isEmpty {
                Color.clear.frame(height: Dimens.verticalSpacing + 4)
                Text(bodyText)
                    .typography(Typography.bodySmall)
                    .lineSpacing(12 * 0.4)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous))
        .padding(Dimens.screenPaddingAll)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .fill(HomeColors.fill)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
}
