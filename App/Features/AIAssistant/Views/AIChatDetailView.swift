import SwiftUI

/// T58 — the destination for `AppRoute.aiChat(conversationID:initialMessage:)`
/// (a *different* screen instance from `AIChatHomeView`'s tab root; reached
/// by pushing that route from elsewhere in the app — wiring an actual entry
/// point to it is a separate task, not this one). Resolves to a conversation
/// id first — the one it's given, or a freshly created one — then mounts
/// `AIChatConversationView` (`Views/AIChatHomeView.swift`) for it, the same
/// shared transcript-plus-input-bar UI the tab root uses, rather than a
/// second copy of that UI.
///
/// Gets its "Chat" navigation title for free from `AppShellView`'s existing
/// `AppRoute.placeholderTitle` switch (already has `case .aiChat: "Chat"`)
/// — no custom nav bar or title added here, per this task's own
/// instruction.
struct AIChatDetailView: View {
    let conversationID: String?
    let initialMessage: String?

    @State private var resolvedConversationID: String?
    @State private var isResolving = false
    @State private var resolutionError: String?

    private let repository: any AIChatRepository = DependencyContainer.current.resolve()
    private let logger = AppLogger(category: .content)

    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let resolvedConversationID {
                // `AIChatConversationView` owns the `hasSentInitialMessage`
                // guard that actually prevents a duplicate auto-send on
                // re-appearance (see that type's own doc comment in
                // `Views/AIChatHomeView.swift`) — nothing further is tracked
                // here for that.
                AIChatConversationView(conversationID: resolvedConversationID, initialMessage: initialMessage)
            } else if let resolutionError {
                ErrorStateView(
                    title: "Couldn't start this chat",
                    message: resolutionError,
                    onRetry: { Task { await resolve() } }
                )
            } else {
                LoadingStateView()
            }
        }
        .background(theme.color(.backgroundPrimary))
        .task {
            await resolveIfNeeded()
        }
    }

    private func resolveIfNeeded() async {
        guard resolvedConversationID == nil, !isResolving else { return }
        await resolve()
    }

    private func resolve() async {
        isResolving = true
        defer { isResolving = false }
        resolutionError = nil

        if let conversationID {
            resolvedConversationID = conversationID
            return
        }

        do {
            let conversation = try await repository.createConversation()
            resolvedConversationID = conversation.id
        } catch let createError {
            logger.warning("create conversation for AIChatDetailView failed: \(createError)")
            resolutionError = "Couldn't start a new conversation. Please try again."
        }
    }
}
