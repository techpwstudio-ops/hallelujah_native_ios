import Foundation
import Observation

/// A single home rail's full paginated content — T29's "see all songs"/
/// "see all artists"/"recent songs" screens (`SeeAllSongPage`/
/// `SeeAllArtistsPage`/`RecentSongsPage`). All three are, on the wire, the
/// exact same call: `HomeRepository.fetchSection(type:uiId:page:)` paged
/// past page 1 (`HOME_V2_API.md` §3.2, "The workhorse of lazy loading" —
/// uniform across every `viewType`). Rather than three near-duplicate
/// screens, this is the one generic consumer, dispatching only at the VIEW
/// layer on `SectionContent`'s case for which card shape to render.
///
/// Dart's V1 equivalents (`HomeViewMoreSongsBloc`) hit the legacy
/// `getHomeByTypeApi` instead — functionally identical pagination, just an
/// older endpoint; T29 builds against the V2 `/section` contract T28
/// already wired, not a new V1 client.
@Observable
@MainActor
final class SectionDetailViewModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded(SectionContent)
        case empty
        case failed
    }

    let uiId: String
    let title: String
    let contentType: HomeContentType
    private(set) var state: LoadState = .loading
    private(set) var isLoadingMore = false

    private let repository: any HomeRepository
    private let logger = AppLogger(category: .content)
    private var loadTask: Task<Void, Never>?

    init(uiId: String, title: String, contentType: HomeContentType, container: DependencyContainer = .current) {
        self.uiId = uiId
        self.title = title
        self.contentType = contentType
        repository = container.resolve()
    }

    func loadIfNeeded() async {
        guard case .loading = state, loadTask == nil else { return }
        await load(page: 1)
    }

    func refresh() async {
        await load(page: 1)
    }

    /// Same `hasMore`-driven rule as `HomeFeedViewModel.loadMore(uiId:)` —
    /// never row count.
    func loadMore() {
        guard case .loaded(let content) = state, content.hasMore, loadTask == nil else { return }
        isLoadingMore = true
        loadTask = Task {
            defer {
                isLoadingMore = false
                loadTask = nil
            }
            do {
                let outcome = try await repository.fetchSection(
                    type: contentType, uiId: uiId, page: content.currentPage + 1
                )
                if case .loaded(let section) = outcome {
                    state = .loaded(content.appending(section.content))
                }
                // `.empty`/`.degraded`/`.malformed` on a page-2+ fetch just
                // leaves what's already on screen, same as
                // `HomeFeedViewModel.fetchSectionAndApply`'s page-2+ cases.
            } catch {
                logger.warning("section \(self.uiId) page \(content.currentPage + 1) failed: \(error)")
            }
        }
    }

    private func load(page: Int) async {
        state = .loading
        loadTask = Task {
            defer { loadTask = nil }
            do {
                let outcome = try await repository.fetchSection(type: contentType, uiId: uiId, page: page)
                switch outcome {
                case .loaded(let section): state = .loaded(section.content)
                case .empty: state = .empty
                case .degraded, .malformed: state = .failed
                }
            } catch {
                logger.warning("section \(self.uiId) page \(page) failed: \(error)")
                state = .failed
            }
        }
        await loadTask?.value
    }
}
