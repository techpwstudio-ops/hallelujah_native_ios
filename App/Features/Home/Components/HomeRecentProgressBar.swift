import SwiftUI

/// `_PlaylistProgressBar` (`home_recent_mixed_row.dart`): a 3pt bar along the
/// bottom edge of a "Continue Your Journey" card showing how many DISTINCT
/// songs of the container have been played (`PlaylistProgressStore`). Renders
/// nothing for a bare song, an artist, or a container nothing has been played
/// from yet. Track `#000 @ 45%`, fill white, bottom corners follow the cover.
///
/// Dart reads the denominator from its Realm cache. Native has no such cache,
/// so the total is fetched lazily — and only once something has been played —
/// then memoised in `HomeProgressTotals`.
struct HomeRecentProgressBar: View {
    let item: RecentContentItem

    @State private var store: PlaylistProgressStore = DependencyContainer.current.resolve()
    @State private var total: Int?

    private static let height: CGFloat = 3

    var body: some View {
        Group {
            if let key = Self.progressKey(for: item),
               let total,
               let progress = store.progress(forKey: key, totalSongs: total) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.45)
                        Color.white.frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: Self.height)
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: Dimens.cornerRadiusSmall,
                    bottomTrailingRadius: Dimens.cornerRadiusSmall
                ))
                .accessibilityHidden(true)
            }
        }
        .task(id: item.id) { await loadTotalIfNeeded() }
    }

    /// `PlaylistProgressService.keyFor(itemType, entityId)`; nil for anything
    /// Dart draws no bar for.
    static func progressKey(for item: RecentContentItem) -> String? {
        guard let entityId = item.entityId, !item.isSong else { return nil }
        switch item.itemType {
        case "companyPlaylist", "album", "season", "userPlaylist":
            return PlaylistProgressStore.key(playerType: item.itemType, containerId: entityId)
        default:
            return nil
        }
    }

    private func loadTotalIfNeeded() async {
        guard let key = Self.progressKey(for: item), let entityId = item.entityId else { return }
        if let cached = HomeProgressTotals.shared.total(for: key) {
            total = cached
            return
        }
        // Nothing played yet: no bar is possible, so skip the request.
        guard store.playedCount(forKey: key) > 0 else {
            // Re-check as soon as a first play is recorded.
            await waitForFirstPlay(key: key)
            guard !Task.isCancelled else { return }
            await loadTotalIfNeeded()
            return
        }
        let fetched = await HomeProgressTotals.fetchTotal(itemType: item.itemType, entityId: entityId)
        guard !Task.isCancelled else { return }
        if let fetched, fetched > 0 {
            HomeProgressTotals.shared.set(fetched, for: key)
            total = fetched
        }
    }

    private func waitForFirstPlay(key: String) async {
        while !Task.isCancelled, store.playedCount(forKey: key) == 0 {
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// In-memory denominators for `HomeRecentProgressBar`.
@MainActor
final class HomeProgressTotals {
    static let shared = HomeProgressTotals()
    private var totals: [String: Int] = [:]

    func total(for key: String) -> Int? { totals[key] }
    func set(_ value: Int, for key: String) { totals[key] = value }

    /// Song count of a container: the paginated envelope's `total` for
    /// playlists/albums/seasons, `songsCount` for the listener's own playlist.
    static func fetchTotal(itemType: String, entityId: String) async -> Int? {
        let container = DependencyContainer.current
        switch itemType {
        case "companyPlaylist":
            let repository: any PlaylistRepository = container.resolve()
            return (try? await repository.fetchSongs(playlistId: entityId, owner: .company, page: 1))?.total
        case "album", "season":
            let repository: any PlaylistRepository = container.resolve()
            let page = try? await repository.fetchSongs(
                playlistId: entityId, owner: .creator(id: nil, name: nil), page: 1
            )
            return page?.total
        case "userPlaylist":
            let repository: any UserPlaylistRepository = container.resolve()
            return (try? await repository.fetchPlaylist(id: entityId))?.songsCount
        default:
            return nil
        }
    }
}
