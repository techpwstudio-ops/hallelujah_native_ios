import SwiftUI

/// T58 — the AI Assistant tab root. Ports the Flutter app's `AiPage`
/// (`lib/views/ai/ai_page.dart`). Owns a local, optional `conversationID`:
/// `nil` shows a branded empty state plus suggestion chips; non-`nil` mounts
/// `AIChatConversationView` (below) inline for that conversation.
///
/// `AIChatDetailView.swift` is a *different* screen instance — the pushed
/// `AppRoute.aiChat` destination reached from elsewhere in the app — so
/// rather than duplicate the scrolling-transcript-plus-input-bar UI the way
/// the Dart `AiPage`/`AiChatPage` pair does, both files mount the same
/// `AIChatConversationView` defined at the bottom of this file (this task
/// could only create the 6 files it was given, none of them a dedicated
/// third file for this shared piece).
///
/// `AISuggestionChip(suggestion:action:)` is built in parallel by another
/// agent — not part of this task — and referenced here by name/signature
/// only.
struct AIChatHomeView: View {
    @State private var conversationID: String?
    @State private var pendingInitialMessage: String?
    @State private var suggestionsViewModel = AISuggestionsViewModel()
    @State private var isStartingConversation = false
    @State private var startError: String?

    /// Resolved from the container (not constructed locally) so this
    /// screen and `AIChatHistoryView` (a separate screen this task doesn't
    /// build) share the exact same instance — `AIChatNavigationStore`'s own
    /// doc comment describes it as the bridge between the two.
    @State private var navigationStore: AIChatNavigationStore = DependencyContainer.current.resolve()

    private let repository: any AIChatRepository = DependencyContainer.current.resolve()
    private let logger = AppLogger(category: .content)

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let conversationID {
                // `.id(conversationID)` gives every distinct conversation a
                // fresh `AIChatConversationView` identity — a fresh
                // `AIChatViewModel` and a fresh `hasSentInitialMessage`
                // guard — rather than one instance being silently reused
                // across "New Chat" taps.
                AIChatConversationView(conversationID: conversationID, initialMessage: pendingInitialMessage)
                    .id(conversationID)
            } else {
                emptyState
            }
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("History") {
                    coordinator.push(.aiHistory)
                }
            }
            if conversationID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Chat") {
                        conversationID = nil
                        pendingInitialMessage = nil
                    }
                }
            }
        }
        .task {
            await suggestionsViewModel.load()
        }
        .onChange(of: navigationStore.pendingConversationID) { _, newValue in
            guard let newValue else { return }
            pendingInitialMessage = nil
            conversationID = newValue
            navigationStore.pendingConversationID = nil
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Spacer(minLength: Spacing.xl)

                VStack(spacing: Spacing.md) {
                    theme.icon(.tabAI)
                        .font(.system(size: 40))
                        .foregroundStyle(theme.color(.brandPrimary))
                    Text("AI Assistant")
                        .typography(Typography.headlineMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                    Text("Ask about songs, sermons, or anything else in the app.")
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textSecondary))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.xl)

                if let startError {
                    Text(startError)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.statusError))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                }

                if !suggestionsViewModel.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(suggestionsViewModel.suggestions) { suggestion in
                                AISuggestionChip(suggestion: suggestion) {
                                    startConversation(with: suggestion)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                    .disabled(isStartingConversation)
                } else if suggestionsViewModel.isLoading {
                    LoadingStateView()
                }

                Spacer(minLength: Spacing.xxl)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Creates a new conversation, then sets `conversationID` with the
    /// suggestion's text queued as `pendingInitialMessage` — the fresh
    /// `AIChatConversationView` this produces (via `.id(conversationID)`)
    /// sends it automatically on mount, the same pending-initial-message
    /// path `AIChatDetailView` uses for its own `initialMessage` parameter.
    private func startConversation(with suggestion: AISuggestion) {
        guard !isStartingConversation else { return }
        isStartingConversation = true
        startError = nil
        Task {
            defer { isStartingConversation = false }
            do {
                let conversation = try await repository.createConversation()
                pendingInitialMessage = suggestion.text
                conversationID = conversation.id
            } catch let createError {
                logger.warning("create conversation from suggestion failed: \(createError)")
                startError = "Couldn't start a new conversation. Please try again."
            }
        }
    }
}

/// T58 — the scrolling transcript plus input bar shared by `AIChatHomeView`
/// (above) and `AIChatDetailView.swift`, so the two mount identical UI
/// instead of copy-pasting it (this task's own instruction: "prioritize
/// correctness over abstraction" only if factoring isn't easy — it is,
/// since both call sites just need a conversation id and an optional
/// initial message). Owns its own `AIChatViewModel`.
///
/// `initialMessage`, if non-empty, is sent automatically exactly once on
/// first appearance; `hasSentInitialMessage` guards a resend if this exact
/// view instance re-appears (e.g. this screen is popped-to and shown again
/// without being torn down) — the same guard `AIChatDetailView` relies on
/// for its own double-send protection, since it mounts this same view.
struct AIChatConversationView: View {
    let conversationID: String
    var initialMessage: String? = nil

    @State private var viewModel: AIChatViewModel
    @State private var hasSentInitialMessage = false

    @Environment(\.appTheme) private var theme

    init(conversationID: String, initialMessage: String? = nil) {
        self.conversationID = conversationID
        self.initialMessage = initialMessage
        _viewModel = State(initialValue: AIChatViewModel(conversationID: conversationID))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            AIChatInputBar(
                isSending: viewModel.isSending,
                isStreaming: viewModel.isStreaming,
                onSend: { text in
                    Task { await viewModel.sendMessage(payload: AISendPayload(message: text, attachments: [])) }
                },
                onStop: {
                    viewModel.cancelStream()
                }
            )
        }
        .background(theme.color(.backgroundPrimary))
        .task {
            await viewModel.loadMessages()
            await sendInitialMessageIfNeeded()
        }
    }

    // MARK: - Transcript

    /// `viewModel.messages` is newest-first (index 0 = latest — see
    /// `AIChatViewModel`'s own doc comment); reversed here, for display
    /// only, into the conventional oldest-at-top/newest-at-bottom order a
    /// chat transcript reads in.
    private var orderedMessages: [AIMessage] {
        Array(viewModel.messages.reversed())
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    if viewModel.isInitialLoading {
                        LoadingStateView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = viewModel.error, orderedMessages.isEmpty {
                        ErrorStateView(
                            title: "Couldn't load this chat",
                            message: error,
                            onRetry: { Task { await viewModel.loadMessages() } }
                        )
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if orderedMessages.isEmpty {
                        EmptyStateView(
                            icon: .tabAI,
                            title: "No messages yet",
                            message: "Say something to get started."
                        )
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        if viewModel.isLoadingMore {
                            LoadingStateView()
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        ForEach(Array(orderedMessages.enumerated()), id: \.element.id) { index, message in
                            AIChatMessageBubble(
                                message: message,
                                onRetry: { messageID in Task { await viewModel.retry(messageID: messageID) } }
                            )
                            .id(message.id)
                            // Mirrors `UserPlaylistDetailView.songList`'s own
                            // "trigger a couple of rows before the true end"
                            // cushion — here the list end that matters is
                            // the *oldest* end, i.e. the top of this
                            // (reversed-for-display) array, indices 0/1.
                            .onAppear {
                                guard index <= 1, viewModel.hasMore, !viewModel.isLoadingMore else { return }
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.first?.id) { _, _ in
                guard let newestID = viewModel.messages.first?.id else { return }
                withAnimation(MotionCurve.fast) {
                    proxy.scrollTo(newestID, anchor: .bottom)
                }
            }
        }
    }

    private func sendInitialMessageIfNeeded() async {
        guard !hasSentInitialMessage,
              let initialMessage,
              !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        hasSentInitialMessage = true
        await viewModel.sendMessage(payload: AISendPayload(message: initialMessage, attachments: []))
    }
}
