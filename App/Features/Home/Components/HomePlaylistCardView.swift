import SwiftUI

/// One playlist card. Three shapes, each a different Dart widget:
/// - `.album` — `CreatorPlaylistUi` (viewType `playlists`): 98 cover, radius 4,
///   `sm` variant.
/// - `.company` — `_CompanyPlaylistCard` in `HomeCompanyPlaylistRow`
///   (`aiPlaylist`): 98 cover, radius 8, `md`.
/// - `.similar` — `_SimilarCard` in `HomeSimilarPlaylistRow`: 120 cover,
///   radius 8, `md`.
/// All three show the shared two-line card title only and open the
/// playlist's song page.
struct HomePlaylistCardView: View {
    enum Style {
        case album
        case company
        case similar
    }

    let playlist: Playlist
    var style: Style = .company

    @Environment(AppNavigationCoordinator.self) private var coordinator

    static let coverSize: CGFloat = HomeMetrics.coverSize

    var body: some View {
        HomeSquareCard(
            url: HomeArt.url(playlist.image, playlist.imageVariants, style == .album ? .sm : .md),
            size: style == .similar ? HomeMetrics.similarCoverSize : HomeMetrics.coverSize,
            cornerRadius: style == .album ? Dimens.cornerRadiusSmall : Dimens.cornerRadius,
            title: playlist.title
        )
        .contentShape(Rectangle())
        .onTapGesture { coordinator.push(playlist.detailRoute) }
    }
}
