import SwiftUI

/// The AI Assistant tab root. Ports Flutter's `AiPage`
/// (`lib/views/ai/ai_page.dart`): a custom black app bar (logo + gradient
/// "Emet", history button, "New Chat" pill when a chat is open), then either
/// the branded empty state with a row of suggestion chips, or the active
/// conversation, with the input bar pinned below.
struct AIChatHomeView: View {
    @State private var conversationID: String?
    @State private var pendingInitialMessage: String?
    @State private var suggestionsViewModel = AISuggestionsViewModel()
    @State private var suggestionsLoaded = false
    @State private var isCreating = false
    @State private var inputText = ""
    @State private var fallbackSuggestions: [String] = AIChatHomeView.pickFallbackSuggestions()

    @State private var navigationStore: AIChatNavigationStore = DependencyContainer.current.resolve()

    private let repository: any AIChatRepository = DependencyContainer.current.resolve()
    private let logger = AppLogger(category: .content)

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    /// Flutter `_allSuggestions`; three are picked at random each time the page opens.
    private static let allSuggestions: [String] = [
        "Why do I feel anxious all the time?",
        "How do I know God\u{2019}s plan for my life?",
        "How do I stop overthinking?",
        "Why does God feel silent?",
        "How do I make the right decision?",
        "How do I find purpose in life?",
        "How do I forgive someone who hurt me?",
        "How do I grow closer to God?",
        "What should I do when I feel lonely?",
        "How do I deal with failure?",
        "How do I trust God during difficult times?",
        "How can I build stronger relationships?",
        "How do I break bad habits?",
        "How do I find peace in a busy life?",
        "What does the Bible say about the situation I\u{2019}m facing?",
    ]

    private static func pickFallbackSuggestions() -> [String] {
        Array(allSuggestions.shuffled().prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            appBar

            if let conversationID {
                // A fresh identity per conversation gives each its own view
                // model and its own one-shot initial-message guard.
                AIChatConversationView(conversationID: conversationID, initialMessage: pendingInitialMessage)
                    .id(conversationID)
            } else {
                AITtsBar()
                emptyState
                suggestionsRow
                AIChatInputBar(
                    text: $inputText,
                    isBusy: isCreating,
                    isStreaming: false,
                    onVoice: { startVoice() },
                    onSend: { sendFromEmptyState() },
                    onStop: {}
                )
            }
        }
        .background(AIColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await suggestionsViewModel.load()
            suggestionsLoaded = true
        }
        .onChange(of: navigationStore.pendingConversationID) { _, newValue in
            guard let newValue else { return }
            pendingInitialMessage = nil
            conversationID = newValue
            navigationStore.pendingConversationID = nil
        }
    }

    // MARK: - App bar

    private var appBar: some View {
        HStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
            Spacer().frame(width: 6)
            AIGradientText(text: "Emet", font: AIColors.font(22, .bold))

            Spacer(minLength: 0)

            Button {
                coordinator.push(.aiHistory)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History")

            Spacer().frame(width: 4)

            if conversationID != nil {
                Button {
                    resetToEmptyState()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white)
                        Text("New Chat")
                            .font(AIColors.font(13))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AIColors.fill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .padding(.leading, 16)
        .frame(height: 56)
        .background(AIColors.background)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                    Spacer().frame(height: 20)
                    AIGradientText(text: "Ask. Seek. Discover.", font: AIColors.font(26, .bold), vertical: true)
                        .multilineTextAlignment(.center)
                    Spacer().frame(height: 12)
                    Text("Seek guidance, find verses, and understand scripture in a deeper way.")
                        .font(AIColors.font(17))
                        .lineSpacing(17 * (1.4 - 1.15))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionTexts: [String] {
        suggestionsViewModel.suggestions.isEmpty
            ? fallbackSuggestions
            : suggestionsViewModel.suggestions.map { $0.text }
    }

    private var suggestionsRow: some View {
        Group {
            if !suggestionsLoaded {
                HStack {
                    Spacer()
                    AISpinner(tint: AIColors.white38, size: 20)
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(suggestionTexts.enumerated()), id: \.offset) { _, text in
                            AISuggestionChip(text: text, action: {
                                startConversation(with: text)
                            }, height: 88)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(height: 104)
    }

    // MARK: - Actions

    private func resetToEmptyState() {
        conversationID = nil
        pendingInitialMessage = nil
        inputText = ""
    }

    private func sendFromEmptyState() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        startConversation(with: text)
    }

    private func startVoice() {
        coordinator.presentAIAudioConversation(conversationID: conversationID)
    }

    /// Creates a conversation, then mounts it with `message` queued as the
    /// first send (Flutter `_startOrContinueChat`).
    private func startConversation(with message: String) {
        guard !isCreating else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let conversation = try await repository.createConversation()
                pendingInitialMessage = message
                conversationID = conversation.id
            } catch let createError {
                logger.warning("create conversation failed: \(createError)")
                toastCenter.show("Couldn't start a new conversation. Please try again.")
            }
        }
    }
}

/// The scrolling transcript plus input bar shared by `AIChatHomeView` and
/// `AIChatDetailView`. Ports `_ChatView` + the chat input of `AiPage` /
/// `AiChatPage`. Owns its `AIChatViewModel`.
struct AIChatConversationView: View {
    let conversationID: String
    var initialMessage: String? = nil

    @State private var viewModel: AIChatViewModel
    @State private var hasSentInitialMessage = false
    @State private var inputText = ""
    @State private var fadedIn = false

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    init(conversationID: String, initialMessage: String? = nil) {
        self.conversationID = conversationID
        self.initialMessage = initialMessage
        _viewModel = State(initialValue: AIChatViewModel(conversationID: conversationID))
    }

    var body: some View {
        VStack(spacing: 0) {
            AITtsBar()
            messageList
                .opacity(fadedIn ? 1 : 0)
            AIChatInputBar(
                text: $inputText,
                isBusy: viewModel.isSending,
                isStreaming: viewModel.isStreaming,
                onVoice: { coordinator.presentAIAudioConversation(conversationID: conversationID) },
                onSend: { send() },
                onStop: { viewModel.cancelStream() }
            )
        }
        .background(AIColors.background)
        .task {
            await viewModel.loadMessages()
            await sendInitialMessageIfNeeded()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) { fadedIn = true }
        }
        .onChange(of: viewModel.error) { _, newValue in
            if let newValue, !newValue.isEmpty {
                toastCenter.show(newValue)
            }
        }
    }

    // MARK: - Transcript

    /// `viewModel.messages` is newest-first; reversed for display.
    private var orderedMessages: [AIMessage] {
        Array(viewModel.messages.reversed())
    }

    @ViewBuilder
    private var messageList: some View {
        if viewModel.isInitialLoading {
            VStack {
                Spacer()
                AISpinner(tint: AIColors.white38, size: 20)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if viewModel.messages.isEmpty {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if viewModel.isLoadingMore {
                            AISpinner(tint: AIColors.white38, size: 20)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        }
                        ForEach(Array(orderedMessages.enumerated()), id: \.element.id) { index, message in
                            AIChatMessageBubble(
                                message: message,
                                onRetry: viewModel.canRetry(messageID: message.id)
                                    ? { messageID in Task { await viewModel.retry(messageID: messageID) } }
                                    : nil
                            )
                            .id(message.id)
                            .onAppear {
                                guard index <= 1, viewModel.hasMore, !viewModel.isLoadingMore else { return }
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    guard newCount > oldCount, !viewModel.isLoadingMore,
                          let newestID = viewModel.messages.first?.id else { return }
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo(newestID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Sending

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await viewModel.sendMessage(payload: AISendPayload(message: text, attachments: [])) }
    }

    private func sendInitialMessageIfNeeded() async {
        guard !hasSentInitialMessage,
              let initialMessage,
              !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        hasSentInitialMessage = true
        await viewModel.sendMessage(payload: AISendPayload(message: initialMessage, attachments: []))
    }
}
