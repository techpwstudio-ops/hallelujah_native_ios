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
        do {
            let page = try await repository.getConversations(cursor: nil)
            conversations = page.items
            hasMore = page.hasMore
            nextCursor = nil
            isLoading = false
        } catch let loadError {
            logger.warning("load conversations failed: \(loadError)")
            error = "Couldn't load conversations. Please try again."
            isLoading = false
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        do {
            let page = try await repository.getConversations(cursor: nextCursor)
            let existingIDs = Set(conversations.map(\.id))
            conversations.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            hasMore = page.hasMore
            nextCursor = nil
            isLoading = false
        } catch let loadMoreError {
            logger.warning("load more conversations failed: \(loadMoreError)")
            error = "Couldn't load more conversations. Please try again."
            isLoading = false
        }
    }

    /// Creates a new conversation and prepends it to the list. Returns it
    /// on success (a caller typically navigates into it immediately) or
    /// `nil` on failure, with `error` set.
    @discardableResult
    func createConversation() async -> AIConversation? {
        do {
            let conversation = try await repository.createConversation()
            conversations.insert(conversation, at: 0)
            return conversation
        } catch let createError {
            logger.warning("create conversation failed: \(createError)")
            error = "Couldn't start a new conversation. Please try again."
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
            error = "Couldn't delete this conversation. Please try again."
        }
    }
}
