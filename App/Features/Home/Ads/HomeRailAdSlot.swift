import SwiftUI
import Observation

/// Which of a rail's own cards a rail ad stands in for (`RailAdVariant`). The
/// artwork is a square in all three.
enum RailAdVariant {
    /// Artwork with the title under it: song, podcast, playlist and
    /// similar-playlist rails.
    case card
    /// Artwork with one centred line under it: the creators rail. A rounded
    /// square, not the avatar's circle, which would cut the corners off the
    /// advertiser's design.
    case avatar
    /// Artwork with the title laid over a scrim: the episode rail.
    case overlay
}

/// One square ad between two items of a horizontal home rail
/// (`HomeRailAdSlot`, `lib/widgets/home/home_rail_ad_slot.dart`) — see
/// `RailAdLayout` for where these go and `RailAdStore` for what they remember.
///
/// Collapses to nothing (zero width, so the rail closes up over it) until the
/// store holds an ad for `slotId`, and again if the listener closes it.
///
/// OWNS ITS TRAILING GAP: a rail's organic cards carry their own trailing
/// padding, which cannot know whether this slot is showing anything. The slot
/// paints `trailingGap` after itself only while it has a card, so the gap
/// exists exactly when the card does.
@MainActor
struct HomeRailAdSlot: View {
    let slotId: String
    /// Edge of the square artwork — the same as the rail's own cover.
    let size: CGFloat
    var variant: RailAdVariant = .card
    /// Corner radius of the artwork — the same as the rail's own cover.
    var radius: CGFloat = Dimens.cornerRadiusSmall
    /// Space after the card, matching the spacing the rail puts after its own
    /// items. Painted only while the card is.
    var trailingGap: CGFloat = Dimens.horizontalSpacing
    /// Space between the artwork and the line under it (`.card`, `.avatar`).
    var captionGap: CGFloat = Dimens.spacing6
    var store: RailAdStore = .shared

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @State private var ad: AdCreative?
    @State private var adsRepository: AdsRepository = DependencyContainer.current.resolve()

    init(
        slotId: String,
        size: CGFloat,
        variant: RailAdVariant = .card,
        radius: CGFloat = Dimens.cornerRadiusSmall,
        trailingGap: CGFloat = Dimens.horizontalSpacing,
        captionGap: CGFloat = Dimens.spacing6,
        store: RailAdStore = .shared
    ) {
        self.slotId = slotId
        self.size = size
        self.variant = variant
        self.radius = radius
        self.trailingGap = trailingGap
        self.captionGap = captionGap
        self.store = store
        // Seeded from the store so a slot rebuilt on scrolling back opens with
        // its ad instead of collapsed-then-popping-in.
        _ad = State(initialValue: store.adFor(slotId))
    }

    var body: some View {
        Group {
            if let ad, ad.assetUrl != nil {
                card(for: ad)
            } else {
                // Not EmptyView: the load task below must have a view to hang on.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        // Also when the slotId is unchanged: after a pull-to-refresh the store
        // was emptied underneath a view that lived on (`generation` moved).
        .task(id: "\(slotId)|\(store.generation)") {
            ad = store.adFor(slotId)
            await store.load(slotId)
            guard !Task.isCancelled else { return }
            ad = store.adFor(slotId)
        }
    }

    private func card(for ad: AdCreative) -> some View {
        let title = Self.title(of: ad)
        return Group {
            switch variant {
            case .card:
                VStack(alignment: .leading, spacing: 0) {
                    artwork(ad, overlayTitle: nil)
                    if !title.isEmpty {
                        Color.clear.frame(height: captionGap)
                        HomeCardTitleView(title: title)
                    }
                }
            case .avatar:
                VStack(alignment: .center, spacing: 0) {
                    artwork(ad, overlayTitle: nil)
                    if !title.isEmpty {
                        Color.clear.frame(height: captionGap)
                        Text(title)
                            .typography(Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                    }
                }
            case .overlay:
                artwork(ad, overlayTitle: title)
            }
        }
        .frame(width: size, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.trailing, trailingGap)
        // A different creative is a different impression, even in a view that
        // lived on from the last one.
        .modifier(RailAdImpression(ad: ad, confirm: { confirmImpression(ad) }))
        .contentShape(Rectangle())
        .onTapGesture {
            openAdAction(ad, coordinator: coordinator, adsRepository: adsRepository)
        }
    }

    private func confirmImpression(_ ad: AdCreative) {
        if store.claimImpression(slotId, ad) {
            adsRepository.trackImpression(ad.impressionToken)
        }
    }

    /// The ⋮ menu's "close this ad".
    private func dismissAd() -> Bool {
        store.dismiss(slotId)
        ad = nil
        return true
    }

    /// What the ad is called on the card: its headline, else who it is from.
    private static func title(of ad: AdCreative) -> String {
        let headline = ad.headline?.homeTrimmed ?? ""
        if !headline.isEmpty { return headline }
        return ad.advertiserName?.homeTrimmed ?? ""
    }

    /// The square picture with the ad's chrome on it: the "Sponsored" chip, the
    /// ⋮ menu and — for `.overlay` — the title over a scrim.
    private func artwork(_ ad: AdCreative, overlayTitle: String?) -> some View {
        let isOverlay = overlayTitle != nil
        // Tight on a 98-wide cover; roomier on the larger overlay card.
        let inset = isOverlay ? Dimens.spacing8 : Dimens.spacing4

        return ZStack {
            AdRemoteImage(urlString: ad.assetUrl ?? "")
            if let overlayTitle {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0x0D / 255), location: 0),
                        .init(color: Color.black.opacity(0x33 / 255), location: 0.45),
                        .init(color: Color.black.opacity(0xBF / 255), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if !overlayTitle.isEmpty {
                    Text(overlayTitle)
                        .typography(Typography.titleSmall)
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(inset)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            // Top-left over the overlay's picture, because its bottom belongs
            // to the title; bottom-left everywhere else, which leaves the top
            // corner to the ⋮.
            AdSponsoredBadge()
                .minimumScaleFactor(0.5)
                .frame(maxWidth: size - 2 * inset, alignment: .leading)
                .padding(inset)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: isOverlay ? .topLeading : .bottomLeading
                )
            AdOptionsButton(
                ad: ad,
                onDismissAd: { dismissAd() },
                size: Dimens.iconSizeSmall,
                overlaySize: Dimens.spacing24,
                usesSharedHost: true
            )
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Keys the impression trigger to the creative, so a new creative restarts the
/// dwell timer.
private struct RailAdImpression: ViewModifier {
    let ad: AdCreative
    let confirm: () -> Void

    func body(content: Content) -> some View {
        AdImpressionTrigger(onVisible: confirm) { content }
            .id(ad.impressionToken)
    }
}
