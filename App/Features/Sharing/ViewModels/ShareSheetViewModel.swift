import Foundation
import Observation

/// What is being shared — mirrors the `DeepLinkService` outbound methods
/// that actually have a UI entry point in this rewrite (T68). Verse-of-Day
/// and user-playlist sharing are minted by `DeepLinkService` too but have no
/// call site yet (T56 screen not built / T45's own Follow-Share scope cut),
/// so they're deliberately left out of this enum rather than added unused.
enum ShareTarget: Sendable, Equatable {
    case song(id: String)
    case creator(id: String)
    case companyPlaylist(id: String)
    case userPlaylist(id: String)
}

/// Backs `ShareSheetView`. Mints the share link once on appearance and
/// caches it — the picked theme only changes the `?viewType=` suffix
/// appended at use-site, not this fetch.
@MainActor
@Observable
final class ShareSheetViewModel {
    enum State: Equatable {
        case loading
        case loaded(URL)
        case failed
    }

    private(set) var state: State = .loading
    /// The card image the share endpoint returns with the link
    /// (`DeepLink.image`, which is all Flutter's `_openSheet` ever shows).
    /// Preferred over the caller's artwork, which can be missing (a user
    /// playlist whose cover is server-composited, an artist with no image).
    private(set) var cardImageURL: URL?

    let target: ShareTarget
    private let deepLinkService: DeepLinkService
    private let logger = AppLogger(category: .sharing)

    init(target: ShareTarget, deepLinkService: DeepLinkService = .shared) {
        self.target = target
        self.deepLinkService = deepLinkService
    }

    func loadIfNeeded() async {
        guard state == .loading else { return }
        await load()
    }

    func retry() async {
        state = .loading
        await load()
    }

    private func load() async {
        do {
            let link: MintedShareLink
            switch target {
            case .song(let id):
                link = try await deepLinkService.shareLink(.songShare(id: id))
            case .creator(let id):
                link = try await deepLinkService.shareLink(.creatorShare(id: id))
            case .companyPlaylist(let id):
                link = try await deepLinkService.shareLink(.companyPlaylistShare(id: id))
            case .userPlaylist(let id):
                link = try await deepLinkService.shareLink(.userPlaylistShare(id: id))
            }
            cardImageURL = ArtworkURLResolver().resolve(path: link.image, variant: .lg, allowedVariants: link.imageVariants)
            state = .loaded(link.url)
        } catch {
            logger.error("Failed to mint share link for \(target): \(error)")
            state = .failed
        }
    }
}
