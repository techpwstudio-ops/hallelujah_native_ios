import SwiftUI

/// The small "Sponsored" chip (`AdSponsoredBadge`,
/// `lib/widgets/ads/ad_sponsored_badge.dart`): 6/2pt padding, radius 4,
/// `adChipBackground` (black @ 55%), 10pt w600 white. Every ad says the same
/// word, a company's own promo included.
struct AdSponsoredBadge: View {
    var body: some View {
        Text("Sponsored")
            .font(.custom(Typography.fontFamily, size: 10, relativeTo: .caption2).weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, Dimens.spacing6)
            .padding(.vertical, Dimens.spacing2)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .continuous)
                    .fill(Color.black.opacity(0x8C / 255))
            )
    }
}
