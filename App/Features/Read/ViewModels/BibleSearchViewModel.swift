import Foundation
import Observation

/// T55 — drives `BibleSearchSheet`, porting `bible_search_panel.dart`'s
/// three states (recent / loading / response) plus the debounced dispatch
/// that panel's own doc comment implies but doesn't itself contain (that
/// lived in a Dart bloc layer this rewrite doesn't carry over 1:1). Debounce
/// shape mirrors `SearchViewModel` (T40) exactly — same 350ms window, same
/// generation-counter staleness guard — for consistency with this
/// codebase's one other debounced-search view model, not because Dart
/// specifies 350ms here too.
@MainActor
@Observable
final class BibleSearchViewModel {
    static let minQueryLength = 1
    private static let debounceMilliseconds = 350
    /// Matches `BibleSearchService.search`'s own default in `bible_search_service.dart`.
    private static let resultLimit = 20

    private let repository: any BibleOfflineRepository
    let recentSearchStore: BibleRecentSearchStore
    private let logger = AppLogger(category: .content)

    private var generation = 0
    private var lastSearchedQuery = ""
    private var debounceTask: Task<Void, Never>?

    private(set) var queryText = ""
    private(set) var isLoading = false
    private(set) var hasError = false
    private(set) var response: BibleSearchResponse?

    var recent: [BibleSearchResult] { recentSearchStore.entries }

    var hasQuery: Bool {
        !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
        recentSearchStore = container.resolve()
    }

    /// Every keystroke. `languageName` is read fresh from the caller each
    /// time (`ReaderViewModel.currentLanguage`) rather than captured once at
    /// init, since the reader's language can change while the sheet is open.
    func queryChanged(_ text: String, languageName: String) {
        queryText = text
        debounceTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minQueryLength else {
            performClear()
            return
        }

        // Collapse whitespace runs so "John  3:16 " and "John 3:16" are one
        // query; a whitespace-only change keeps the current results.
        let normalized = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if normalized == lastSearchedQuery {
            generation += 1
            isLoading = false
            return
        }

        // Flutter shows the shimmer the moment the query changes, not after
        // the debounce.
        isLoading = true
        hasError = false
        generation += 1
        let thisGeneration = generation
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.debounceMilliseconds))
            guard !Task.isCancelled else { return }
            await self?.performSearch(query: normalized, languageName: languageName, generation: thisGeneration)
        }
    }

    func clearButtonTapped() {
        queryText = ""
        performClear()
    }

    func recordTap(_ result: BibleSearchResult) {
        recentSearchStore.record(result)
    }

    func removeRecent(_ result: BibleSearchResult) {
        recentSearchStore.remove(reference: result.reference)
    }

    /// Closing search (Flutter `_closeSearch`): drop the text and every result.
    func reset() {
        queryText = ""
        performClear()
    }

    private func performClear() {
        lastSearchedQuery = ""
        debounceTask?.cancel()
        generation += 1
        isLoading = false
        hasError = false
        response = nil
    }

    private func performSearch(query: String, languageName: String, generation thisGeneration: Int) async {
        guard thisGeneration == generation else { return }
        lastSearchedQuery = query
        isLoading = true
        hasError = false

        defer {
            if thisGeneration == generation {
                isLoading = false
            }
        }

        do {
            let result = try await repository.search(query: query, languageName: languageName, limit: Self.resultLimit)
            guard thisGeneration == generation else { return }
            response = result
        } catch {
            guard thisGeneration == generation else { return }
            logger.warning("Bible search failed: \(error)")
            hasError = true
            lastSearchedQuery = ""
            response = nil
        }
    }
}
