import Foundation
import Observation

/// Ports the data side of `EpisodesPage` (`lib/views/search/episodes.dart`):
/// its Realm query `type == 'podcasts' and image != ''`, re-derived from a
/// plain in-memory genre fetch (same approach as `BrowseViewModel`).
@MainActor
@Observable
final class EpisodesViewModel {
    private(set) var allGenres: [Genre] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let repository: any GenreRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    var displayedGenres: [Genre] {
        allGenres.filter { $0.type == "podcasts" && $0.image != "" }
    }

    func onAppear() async {
        guard allGenres.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            allGenres = try await repository.fetchGenres()
        } catch {
            logger.warning("podcast genre list load failed: \(error)")
            loadError = "Something went wrong"
        }
        isLoading = false
    }
}
