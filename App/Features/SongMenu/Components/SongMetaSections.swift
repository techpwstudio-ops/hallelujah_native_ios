import SwiftUI
import Observation

/// Backs `SongMetaSections`: the detail-only parts of `SongMetaDataUi`
/// (`lib/widgets/player/song_meta_data.dart`) that follow the lyrics card —
/// the creator card (`CreatorMetaUi`), the credits card (`Credits`) and the
/// "More like this" rail (`RelatedContentRail`).
///
/// The list-view `Song` the player holds carries no bio or per-artist
/// follow flags, so the detail response is fetched here (Dart watches
/// `songByIdProvider`). Follow toggles are optimistic and revert on failure.
@MainActor
@Observable
final class SongMetaSectionsViewModel {
    private(set) var song: Song?
    private(set) var related: RelatedContent = .empty
    private(set) var isLoadingRelated = false
    /// True while the detail for the current track is in flight, so the view
    /// can hold the creator card's space instead of collapsing and popping in.
    private(set) var isLoadingSong = false

    private let songRepository: any SongRepository
    private let creatorRepository: any CreatorRepository
    private let relatedService: RelatedContentService

    init(container: DependencyContainer = .current) {
        songRepository = container.resolve()
        creatorRepository = container.resolve()
        relatedService = container.resolve()
    }

    /// Re-run on every song change, so the rail tracks the current track.
    func load(songId: String, excludeId: String?) async {
        song = nil
        isLoadingSong = true
        if let cached = relatedService.cached(for: songId, excludeId: excludeId) {
            related = cached
        } else {
            related = .empty
            isLoadingRelated = true
        }
        async let detail = try? songRepository.fetchSong(id: songId)
        async let rail = relatedService.fetchForSong(songId, excludeId: excludeId)
        let (loadedSong, loadedRelated) = await (detail, rail)
        guard !Task.isCancelled else { return }
        song = loadedSong
        related = loadedRelated
        isLoadingRelated = false
        isLoadingSong = false
    }

    var mainCreatorID: String? { song.flatMap(SongMenuViewModel.artistID(of:)) }

    func isFollowing(creatorID: String?, fallback: Bool?) -> Bool {
        CreatorFollowStore.shared.isFollowing(creatorID, fallback: fallback)
    }

    /// `applyCreatorFollow` + `CreatorFollowingChangedEvent`.
    /// Returns false when the request failed and the flag was reverted.
    func toggleFollow(creatorID: String, current: Bool) async -> Bool {
        let store = CreatorFollowStore.shared
        let previousState = store.state(for: creatorID)
        store.set(!current, for: creatorID)
        do {
            if current {
                try await creatorRepository.unfollow(creatorId: creatorID)
            } else {
                try await creatorRepository.follow(creatorId: creatorID)
            }
            return true
        } catch {
            store.set(previousState, for: creatorID)
            return false
        }
    }

    /// `Credits`: every primary artist except the song's main creator.
    var creditedArtists: [SongArtistRef] {
        guard let song else { return [] }
        let main = mainCreatorID
        return song.songPrimaryArtists.filter { $0.creatorId != main }
    }
}

/// Creator card, credits card and related rail, in `SongMetaDataUi` order.
/// Place it between the lyrics card and the "Description" label.
struct SongMetaSections: View {
    let songId: String
    /// `sourceIdFromPlayerId(playerType, playerId)` — the playlist or creator
    /// currently playing, never suggested back.
    var excludeId: String?
    var onOpenCreator: ((String) -> Void)?
    var onOpenRelated: ((RelatedItem) -> Void)?
    /// Content rendered between the credits card and the related rail — the
    /// player puts its "Description" block here, matching `SongMetaDataUi`'s
    /// order (creator, credits, description, rail).
    var middle: AnyView?

    @State private var viewModel = SongMetaSectionsViewModel()
    @State private var detailsCreator: Creator?
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    private struct Trigger: Hashable { let songId: String; let excludeId: String? }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let song = viewModel.song {
                creatorCard(song).padding(.vertical, 16)
                creditsCard
                Spacer().frame(height: Dimens.spacing16)
            } else if viewModel.isLoadingSong {
                // Same footprint as the creator card, so swiping to the next
                // track doesn't make everything below jump when it arrives.
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                Spacer().frame(height: Dimens.spacing16)
            }
            if let middle { middle }
            relatedRail
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoadingSong)
        .task(id: Trigger(songId: songId, excludeId: excludeId)) {
            await viewModel.load(songId: songId, excludeId: excludeId)
        }
        .appSheet(isPresented: Binding(get: { detailsCreator != nil }, set: { if !$0 { detailsCreator = nil } }), detents: [.large]) {
            if let detailsCreator { CreatorDetailsSheet(creator: detailsCreator) }
        }
    }

    // MARK: Creator card (`CreatorMetaUi`)

    @ViewBuilder
    private func creatorCard(_ song: Song) -> some View {
        if let creator = song.creator {
            let creatorID = viewModel.mainCreatorID
            ZStack(alignment: .bottomLeading) {
                ArtworkView(
                    url: ArtworkURLResolver().resolve(path: creator.image, variant: .lg, allowedVariants: creator.imageVariants, fallbackName: creator.name),
                    width: UIScreen.main.bounds.width - 2 * Dimens.screenPaddingAll,
                    height: UIScreen.main.bounds.width - 2 * Dimens.screenPaddingAll,
                    cornerRadius: Dimens.cornerRadiusMedium
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.black.opacity(0.4), location: 0.5),
                        .init(color: Color.black.opacity(0.7), location: 0.75),
                        .init(color: Color.black.opacity(0.9), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(creator.name ?? "")
                        .typography(TypographyToken(size: 20, weight: .semibold, lineHeightMultiple: 1.3))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black, radius: 8, x: 0, y: 2)
                    if let bio = creator.bio, !bio.isEmpty {
                        // `ExpandableText(maxLines: 2, onTap: showCreatorDetailsSheet)`:
                        // "Read more" under a clipped bio opens the full one.
                        PlayerExpandableText(
                            text: bio,
                            maxLines: 2,
                            token: TypographyToken(size: 14, weight: .light, lineHeightMultiple: 1.5),
                            color: Color.white.opacity(0.7),
                            linkColor: Color.white.opacity(0.7),
                            onReadMore: { detailsCreator = creator }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { detailsCreator = creator }
                    }
                }
                .padding(16)
            }
            .overlay(alignment: .topTrailing) {
                followButton(creatorID: creatorID, fallback: creator.isFollowing)
                    .padding(12)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .circular))
            .contentShape(Rectangle())
            .onTapGesture { if let creatorID { openCreator(creatorID) } }
        }
    }

    /// `CreatorFollowButton`: 36pt tall, "Follow" / "Following", w600 white.
    private func followButton(creatorID: String?, fallback: Bool?) -> some View {
        let isFollowing = viewModel.isFollowing(creatorID: creatorID, fallback: fallback)
        return Button {
            guard let creatorID else { return }
            Task {
                if await !viewModel.toggleFollow(creatorID: creatorID, current: isFollowing) {
                    toastCenter.show("Network error")
                }
            }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .typography(TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.2))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    isFollowing ? Color.white.opacity(0.12) : Color(red: 0.173, green: 0.173, blue: 0.173),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Credits card (`Credits`)

    @ViewBuilder
    private var creditsCard: some View {
        let artists = viewModel.creditedArtists
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Credits")
                    .typography(TypographyToken(size: 18, weight: .semibold, lineHeightMultiple: 1.3))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                    HStack(spacing: 16) {
                        ArtworkView(
                            url: ArtworkURLResolver().resolve(
                                path: artist.creator?.image, variant: .sm, allowedVariants: artist.creator?.imageVariants
                            ),
                            width: 36, height: 36, cornerRadius: 18
                        )
                        Text(artist.name ?? "")
                            .typography(Typography.titleSmall)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        followButton(creatorID: artist.creatorId, fallback: artist.creator?.isFollowing)
                    }
                    .padding(8)
                }
            }
            .background(Color(red: 0.545, green: 0.765, blue: 0.29).opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
        }
    }

    // MARK: Related rail (`RelatedContentRail`)

    @ViewBuilder
    private var relatedRail: some View {
        if !viewModel.related.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: Dimens.spacing16)
                Text("More like this")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(Color.white)
                Spacer().frame(height: Dimens.sectionHeaderGap)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Dimens.horizontalSpacing) {
                        if viewModel.isLoadingRelated {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: Self.railImageSize, height: Self.railImageSize + 40)
                            }
                        } else {
                            ForEach(viewModel.related.items) { item in
                                relatedCard(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private static let railImageSize: CGFloat = 98

    private func relatedCard(_ item: RelatedItem) -> some View {
        VStack(alignment: .leading, spacing: Dimens.spacing4) {
            ArtworkView(
                url: ArtworkURLResolver().resolve(path: item.image, variant: .md, allowedVariants: item.imageVariants),
                width: Self.railImageSize, height: Self.railImageSize, cornerRadius: Dimens.cornerRadiusSmall
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines))
                    .typography(TypographyToken(size: 14, weight: .semibold, lineHeightMultiple: 1.4))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(item.reasonLabel)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(Color.white.opacity(0.54))
                    .lineLimit(1)
            }
        }
        .frame(width: Self.railImageSize, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { openRelated(item) }
    }

    // MARK: Navigation

    private func openCreator(_ id: String) {
        if let onOpenCreator { onOpenCreator(id); return }
        coordinator.dismissFullScreen()
        coordinator.push(.creatorSongs(creatorID: id, userPlaylistID: nil))
    }

    private func openRelated(_ item: RelatedItem) {
        if let onOpenRelated { onOpenRelated(item); return }
        coordinator.dismissFullScreen()
        switch item.kind {
        case .playlist:
            coordinator.push(.playlistDetail(
                playlistID: item.id, title: item.title, image: item.image, imageVariants: item.imageVariants,
                songsCount: nil, isCompanyOwned: true, creatorID: nil, creatorName: nil
            ))
        case .creator:
            coordinator.push(.creatorSongs(creatorID: item.id, userPlaylistID: nil))
        }
    }
}
