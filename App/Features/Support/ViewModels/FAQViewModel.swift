import Foundation
import Observation

/// Ports `FaqNotifier` (`lib/river_pods/faqProvider.dart`) behind `FAQView`.
/// `SupportRepository.fetchFAQs()`'s own doc comment already records why
/// this is a single-attempt load-with-retry-button rather than Dart's
/// online/offline auto-retry-on-reconnect layer — the same `LoadState`
/// shape `SectionDetailViewModel` already establishes for this app's other
/// network-backed screens, mirrored here for consistency.
@Observable
@MainActor
final class FAQViewModel {
    enum LoadState: Sendable, Equatable {
        case loading
        case loaded([FAQItem])
        case empty
        case failed
    }

    private(set) var state: LoadState = .loading

    private let supportRepository: any SupportRepository
    private let logger = AppLogger(category: .content)
    private var loadTask: Task<Void, Never>?

    init(container: DependencyContainer = .current) {
        supportRepository = container.resolve()
    }

    func loadIfNeeded() async {
        guard case .loading = state, loadTask == nil else { return }
        await load()
    }

    /// `ref.refresh(faqProvider)` (`faqs.dart`'s `onRefresh`) — re-runs the
    /// same single-attempt fetch regardless of the current state.
    func refresh() async {
        await load()
    }

    private func load() async {
        state = .loading
        loadTask = Task {
            defer { loadTask = nil }
            do {
                let faqs = try await supportRepository.fetchFAQs()
                state = faqs.isEmpty ? .empty : .loaded(faqs)
            } catch {
                logger.warning("FAQ load failed: \(error)")
                state = .failed
            }
        }
        await loadTask?.value
    }
}
