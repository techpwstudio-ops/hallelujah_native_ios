import Foundation
import Observation

/// T58 — the AI chat conversation list (history sidebar / picker). Ports
/// the Flutter app's `AiConversationsNotifier`.
@MainActor
@Observable
final class AIConversationsViewModel {
    private(set) var conversations: [AIConversation] = []
    private(set) var isLoading = false
    private(set) var hasMore = false
    /// See `AIChatViewModel.nextCursor`'s doc comment / `AIChatDTOs.swift`'s
    /// `AICursorPageDTO.toPaginated(_:)`: `AIChatRepository`'s
    /// `Paginated<AIConversation>` return type has no cursor field, so this
    /// stays `nil` after every fetch under the current Data layer.
    /// `loadMore()` still threads it through `getConversations(cursor:)` as
    /// specified, deduping by id on append so re-fetching the same page
    /// can't insert duplicate `Identifiable` rows.
    private(set) var nextCursor: String?
    /// Conversations are page-number paginated (`AiConversationsState.page`).
    private var currentPage = 1
    private(set) var error: String?

    private let repository: any AIChatRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    /// Resets the list, then fetches the first page.
    func load() async {
        isLoading = true
        error = nil
        conversations = []
        hasMore = false
        nextCursor = nil
        currentPage = 1
        do {
            let page = try await repository.getConversations(cursor: nil, page: 1)
            conversations = page.items
            hasMore = page.hasMore
            nextCursor = page.nextCursor
            currentPage = page.page
            isLoading = false
        } catch let loadError {
            logger.warning("load conversations failed: \(loadError)")
            error = AIErrorParser.message(for: loadError, fallback: String(localized: "Couldn't load conversations. Please try again."))
            isLoading = false
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        do {
            let page = try await repository.getConversations(cursor: nextCursor, page: currentPage + 1)
            let existingIDs = Set(conversations.map(\.id))
            conversations.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            hasMore = page.hasMore
            nextCursor = page.nextCursor
            currentPage = max(page.page, currentPage + 1)
            isLoading = false
        } catch let loadMoreError {
            logger.warning("load more conversations failed: \(loadMoreError)")
            error = AIErrorParser.message(for: loadMoreError, fallback: String(localized: "Couldn't load more conversations. Please try again."))
            isLoading = false
        }
    }

    /// Creates a new conversation and prepends it to the list. Returns it
    /// on success (a caller typically navigates into it immediately) or
    /// `nil` on failure, with `error` set.
    @discardableResult
    func createConversation(title: String? = nil) async -> AIConversation? {
        do {
            let conversation = try await repository.createConversation(title: title)
            conversations.insert(conversation, at: 0)
            return conversation
        } catch let createError {
            logger.warning("create conversation failed: \(createError)")
            error = AIErrorParser.message(for: createError, fallback: String(localized: "Couldn't start a new conversation. Please try again."))
            return nil
        }
    }

    /// Removes the conversation locally only on a confirmed server delete;
    /// on failure the array is left untouched and `error` is set.
    func deleteConversation(id: String) async {
        do {
            try await repository.deleteConversation(id: id)
            conversations.removeAll { $0.id == id }
        } catch let deleteError {
            logger.warning("delete conversation \(id) failed: \(deleteError)")
            error = AIErrorParser.message(for: deleteError, fallback: String(localized: "Couldn't delete this conversation. Please try again."))
        }
    }
}
