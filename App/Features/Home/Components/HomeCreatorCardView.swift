import SwiftUI

/// One card in a `creators`-viewType rail — `CreatorGridItem`: an 80pt circular
/// avatar (`sm` variant), 8pt gap and a centred `bodySmall` w500 name. Tapping
/// opens the artist page (`CreatorSongsPage`).
struct HomeCreatorCardView: View {
    let creator: Creator
    /// The creators rail spaces its cards by `Dimens.horizontalGapMedium` (8).
    var trailingGap: CGFloat = Dimens.horizontalGapMedium

    @Environment(AppNavigationCoordinator.self) private var coordinator

    static let avatarSize: CGFloat = HomeMetrics.creatorAvatarSize

    var body: some View {
        VStack(spacing: HomeMetrics.creatorAvatarToNameGap) {
            ArtworkView(
                url: HomeArt.url(creator.image, creator.imageVariants, .sm),
                width: Self.avatarSize,
                height: Self.avatarSize,
                cornerRadius: Self.avatarSize / 2
            )
            Text(creator.name ?? "")
                .typography(Typography.bodySmall)
                .fontWeight(.medium)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.avatarSize, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            coordinator.push(.creatorSongs(creatorID: creator.creatorId, userPlaylistID: nil))
        }
        .padding(.trailing, trailingGap)
    }
}

/// One card in a `podcasts`-viewType rail — `_PodcastItem`: a 98 square cover
/// (radius 4, `md`) with the shared two-line card title; opens the creator.
struct HomePodcastCardView: View {
    let creator: Creator

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        HomeSquareCard(
            url: HomeArt.url(creator.image, creator.imageVariants, .md),
            title: creator.name ?? ""
        )
        .contentShape(Rectangle())
        .onTapGesture {
            coordinator.push(.creatorSongs(creatorID: creator.creatorId, userPlaylistID: nil))
        }
    }
}
