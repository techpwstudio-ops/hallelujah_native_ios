import Foundation

/// Same shape as `FavouriteSongsViewModel`'s own private page struct — see
/// that file's doc comment for why this isn't generalized into one shared
/// type.
private struct VerseOfDayCommentsPage: Sendable {
    var items: [VerseOfDayComment] = []
    var page = 0
    var hasMore = true
    var isLoading = false
}

/// T56 — `VerseOfDayCommentsSheet`'s state. Ports the server-facing half of
/// `VerseOfDayCommentBloc` (`lib/blocs/verse_of_day_comments/bloc.dart`):
/// page-based load, post-comment (prepended — `PaginationModel.addId`
/// inserts at index 0, confirmed against `lib/models/CategoryPageData.dart`,
/// so a new comment appears above older ones, not below), and per-comment
/// like toggle updated in place.
@MainActor
@Observable
final class VerseOfDayCommentsViewModel {
    let verseOfDayId: String

    private var page = VerseOfDayCommentsPage()
    private let repository: any VerseOfDayRepository
    private let logger = AppLogger(category: .content)

    private(set) var isAddingComment = false

    init(verseOfDayId: String, container: DependencyContainer = .current) {
        self.verseOfDayId = verseOfDayId
        repository = container.resolve()
    }

    var comments: [VerseOfDayComment] { page.items }
    var isLoadingComments: Bool { page.isLoading }
    var hasLoadedOnce: Bool { page.page > 0 }

    func onAppear() async {
        guard !hasLoadedOnce, !page.isLoading else { return }
        await loadMoreComments()
    }

    func loadMoreCommentsIfNeeded(currentItem: VerseOfDayComment) async {
        guard let index = page.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard index >= page.items.count - 3 else { return }
        await loadMoreComments()
    }

    func loadMoreComments() async {
        guard !page.isLoading, page.hasMore else { return }
        page.isLoading = true
        do {
            let result = try await repository.fetchComments(verseOfDayId: verseOfDayId, page: page.page + 1)
            page.items.append(contentsOf: result.items)
            page.page = result.page
            page.hasMore = result.hasMore
        } catch {
            logger.warning("verse of day comments page load failed: \(error)")
            if page.page == 0 {
                page.page = 1
                page.hasMore = false
            }
        }
        page.isLoading = false
    }

    func postComment(content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAddingComment else { return }
        isAddingComment = true
        defer { isAddingComment = false }
        do {
            let comment = try await repository.addComment(verseOfDayId: verseOfDayId, content: trimmed)
            page.items.insert(comment, at: 0)
        } catch {
            logger.warning("verse of day post comment failed: \(error)")
        }
    }

    func toggleCommentLike(_ comment: VerseOfDayComment) async {
        guard let index = page.items.firstIndex(where: { $0.id == comment.id }) else { return }
        do {
            let updated = try await repository.toggleCommentLike(commentId: comment.id)
            page.items[index] = updated
        } catch {
            logger.warning("verse of day comment like toggle failed: \(error)")
        }
    }
}
