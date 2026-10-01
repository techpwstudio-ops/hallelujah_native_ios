import Foundation

/// Ports `_SearchPageState` (`lib/views/search/search_page.dart`) — the
/// Search tab's landing screen. Dart drives its grid from a reactive Realm
/// query (`realm.query<Genre>(r"type == $0 and image != $1",
/// [songType.name, ''])`); this app has no local content cache yet (same gap
/// `SearchViewModel`'s own doc comment notes for recent searches), so
/// `displayedGenres` below re-derives the same two predicates from a plain
/// in-memory fetch instead.
@MainActor
@Observable
final class BrowseViewModel {
    private(set) var allGenres: [Genre] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    var selectedType: HomeContentType = .music

    private let repository: any GenreRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    /// `search_page.dart`'s Realm predicate, `type == $0 and image != $1`:
    /// matching `selectedType`, and excluding genres with an explicit empty-
    /// string image. Realm's `!=` treats null and `""` as distinct (checked
    /// against realm-core's `StringData` comparison, the pinned Core version
    /// behind `realm: 20.2.0`) — a `nil` image genre still matches and stays
    /// in the grid; only an explicit `""` drops it. `$0.image != ""` mirrors
    /// that exactly (`nil != ""` is true in Swift too).
    var displayedGenres: [Genre] {
        allGenres.filter { $0.type == selectedType.rawValue && $0.image != "" }
    }

    func onAppear() async {
        guard allGenres.isEmpty, !isLoading else { return }
        await loadGenres()
    }

    func loadGenres() async {
        isLoading = true
        loadError = nil
        do {
            allGenres = try await repository.fetchGenres()
        } catch {
            logger.warning("genre list load failed: \(error)")
            loadError = "Something went wrong"
        }
        isLoading = false
    }
}
