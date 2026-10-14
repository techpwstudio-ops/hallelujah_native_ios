import Foundation
import Observation

/// T58 — the AI chat empty-state suggestion chips. Ports the Flutter app's
/// `AiSuggestionsNotifier`: a non-critical affordance, so a failure (even
/// after one retry) is swallowed rather than surfaced as an error — an
/// empty suggestion list is a perfectly fine thing for the view to show.
@MainActor
@Observable
final class AISuggestionsViewModel {
    private(set) var suggestions: [AISuggestion] = []
    private(set) var isLoading = false

    private let repository: any AIChatRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    /// Fetches suggestions; on failure, retries exactly once after a
    /// 1-second delay. A second failure just leaves `suggestions` empty —
    /// no `error` property exists on this view model by design, matching
    /// the Flutter app's own silent-failure behavior here.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            suggestions = try await repository.getSuggestions()
        } catch let firstError {
            logger.warning("load suggestions failed, retrying once: \(firstError)")
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                suggestions = try await repository.getSuggestions()
            } catch let secondError {
                logger.warning("retry load suggestions failed, leaving empty: \(secondError)")
                suggestions = []
            }
        }
    }
}
