import Foundation

/// Same shape as `FavouriteSongsViewModel`'s own private page struct — see
/// that file's doc comment for why this isn't generalized into one shared
/// type.
private struct VerseOfDayHistoryPage: Sendable {
    var items: [VerseOfDay] = []
    var page = 0
    var hasMore = true
    var isLoading = false
}

/// T56 — `VerseOfDayHistorySheet`'s state. Ports the load half of
/// `VerseOfDayHistoryBloc` (`lib/blocs/verse_of_day_history/bloc.dart`)'s
/// `_load`: page-based, newest first, against `GET /book/verse-of-day/history`.
@MainActor
@Observable
final class VerseOfDayHistoryViewModel {
    private var page = VerseOfDayHistoryPage()
    private let repository: any VerseOfDayRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    var verses: [VerseOfDay] { page.items }
    var isLoadingHistory: Bool { page.isLoading }
    var hasLoadedOnce: Bool { page.page > 0 }

    func onAppear() async {
        guard !hasLoadedOnce, !page.isLoading else { return }
        await loadMoreHistory()
    }

    func loadMoreHistoryIfNeeded(currentItem: VerseOfDay) async {
        guard let index = page.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= page.items.count - 3 else { return }
        await loadMoreHistory()
    }

    func loadMoreHistory() async {
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        do {
            let result = try await repository.fetchHistory(page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
        } catch {
            logger.warning("verse of day history page load failed: \(error)")
            if page.page == 0 {
                page.page = 1
                page.hasMore = false
            }
        }
        page.isLoading = false
    }
}
