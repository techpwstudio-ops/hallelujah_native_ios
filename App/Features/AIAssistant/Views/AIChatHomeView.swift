import PhotosUI
import SwiftUI
import UIKit

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
    @State private var attachments: [AIPendingAttachment] = []
    @State private var pendingInitialAttachments: [AIAttachmentPayload] = []
    @State private var isPhotoPickerPresented = false
    @State private var photoSelection: PhotosPickerItem?
    /// Indices into `allSuggestions`, not text: the chips are translated
    /// when drawn, so they follow an app-language change.
    @State private var fallbackSuggestionIndices: [Int] = AIChatHomeView.pickFallbackSuggestions()

    @State private var navigationStore: AIChatNavigationStore = DependencyContainer.current.resolve()

    private let repository: any AIChatRepository = DependencyContainer.current.resolve()
    private let uploadRepository: any UploadRepository = DependencyContainer.current.resolve()
    private let logger = AppLogger(category: .content)

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    /// Flutter `_allSuggestions`; three are picked at random each time the page opens.
    /// Built per read, like Flutter's ("the chips must follow the app
    /// language"): a `static let` translated them once, in whatever language
    /// the app had at that moment, and kept that language for good.
    private static var allSuggestions: [String] { [
        String(localized: "Why do I feel anxious all the time?"),
        String(localized: "How do I know God\u{2019}s plan for my life?"),
        String(localized: "How do I stop overthinking?"),
        String(localized: "Why does God feel silent?"),
        String(localized: "How do I make the right decision?"),
        String(localized: "How do I find purpose in life?"),
        String(localized: "How do I forgive someone who hurt me?"),
        String(localized: "How do I grow closer to God?"),
        String(localized: "What should I do when I feel lonely?"),
        String(localized: "How do I deal with failure?"),
        String(localized: "How do I trust God during difficult times?"),
        String(localized: "How can I build stronger relationships?"),
        String(localized: "How do I break bad habits?"),
        String(localized: "How do I find peace in a busy life?"),
        String(localized: "What does the Bible say about the situation I\u{2019}m facing?"),
    ] }

    private static func pickFallbackSuggestions() -> [Int] {
        Array(allSuggestions.indices.shuffled().prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            appBar

            if let conversationID {
                // A fresh identity per conversation gives each its own view
                // model and its own one-shot initial-message guard.
                AIChatConversationView(
                    conversationID: conversationID,
                    initialMessage: pendingInitialMessage,
                    initialAttachments: pendingInitialAttachments
                )
                .id(conversationID)
            } else {
                AITtsBar()
                emptyState
                suggestionsRow
                AIChatInputBar(
                    text: $inputText,
                    attachments: attachments,
                    isBusy: isCreating,
                    isStreaming: false,
                    onVoice: VoiceFeature.showVoiceEntryPoint ? { startVoice() } : nil,
                    onAttach: { isPhotoPickerPresented = true },
                    onRemoveAttachment: { index in
                        if attachments.indices.contains(index) { attachments.remove(at: index) }
                    },
                    onSend: { sendFromEmptyState() },
                    onStop: {}
                )
            }
        }
        .background(AIColors.background.ignoresSafeArea())
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            photoSelection = nil
            Task { await attach(item) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await suggestionsViewModel.load()
            suggestionsLoaded = true
        }
        .onChange(of: navigationStore.pendingConversationID) { _, newValue in
            guard let newValue else { return }
            pendingInitialMessage = nil
            pendingInitialAttachments = []
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

            GlassIconButton(
                systemName: "clock.arrow.circlepath",
                size: 44,
                iconSize: 20,
                accessibilityLabel: "History"
            ) {
                coordinator.push(.aiHistory)
            }

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
                    .frame(minHeight: 44)
                    .glassCapsule(interactive: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .padding(.leading, 16)
        .frame(height: 56)
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
                    AIGradientText(text: String(localized: "Ask. Seek. Discover."), font: AIColors.font(26, .bold), vertical: true)
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
                .contentShape(Rectangle())
                .onTapGesture { aiDismissKeyboard() }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Suggestions

    private var suggestionTexts: [String] {
        suggestionsViewModel.suggestions.isEmpty
            ? fallbackSuggestionIndices.map { Self.allSuggestions[$0] }
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
        pendingInitialAttachments = []
        inputText = ""
        attachments = []
    }

    private func sendFromEmptyState() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // `_onSendTap`: wait for uploads, then only finished uploads go out.
        if attachments.contains(where: { $0.isUploading }) { return }
        let uploaded = AIAttachmentStaging.payloads(from: attachments)
        inputText = ""
        attachments = []
        aiDismissKeyboard()
        startConversation(with: text, attachments: uploaded)
    }

    /// `_pickFile` + `_uploadAttachment` for the empty state (the strip can
    /// hold several here, unlike the conversation view).
    private func attach(_ item: PhotosPickerItem) async {
        guard let staged = await AIAttachmentStaging.stage(item) else {
            toastCenter.show("File upload failed. Please try again.")
            return
        }
        attachments.append(staged.pending)
        let id = staged.pending.id
        if let key = await AIAttachmentStaging.upload(staged, using: uploadRepository) {
            if let index = attachments.firstIndex(where: { $0.id == id }) {
                attachments[index].isUploading = false
                attachments[index].uploadedKey = key
            }
        } else {
            attachments.removeAll { $0.id == id }
            toastCenter.show("File upload failed. Please try again.")
        }
    }

    private func startVoice() {
        coordinator.presentAIAudioConversation(conversationID: conversationID)
    }

    /// Creates a conversation, then mounts it with `message` queued as the
    /// first send (Flutter `_startOrContinueChat`).
    private func startConversation(with message: String, attachments: [AIAttachmentPayload] = []) {
        guard !isCreating else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                // `_startOrContinueChat`: the title is the first 60 characters.
                let title = message.isEmpty ? nil : (message.count > 60 ? String(message.prefix(60)) + "..." : message)
                let conversation = try await repository.createConversation(title: title)
                pendingInitialMessage = message
                pendingInitialAttachments = attachments
                conversationID = conversation.id
            } catch let createError {
                logger.warning("create conversation failed: \(createError)")
                let text = AIErrorParser.parse(createError)
                if !text.isEmpty { toastCenter.show(text) }
            }
        }
    }
}

/// Flutter `onTapOutside` / send both `unfocus()` the composer.
@MainActor
private func aiDismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// The scrolling transcript plus input bar shared by `AIChatHomeView` and
/// `AIChatDetailView`. Ports `_ChatView` + the chat input of `AiPage` /
/// `AiChatPage`. Owns its `AIChatViewModel`.
struct AIChatConversationView: View {
    let conversationID: String
    var initialMessage: String? = nil
    var initialAttachments: [AIAttachmentPayload] = []

    @State private var viewModel: AIChatViewModel
    @State private var hasSentInitialMessage = false
    @State private var inputText = ""
    @State private var fadedIn = false
    @State private var attachments: [AIPendingAttachment] = []
    @State private var isPhotoPickerPresented = false
    @State private var photoSelection: PhotosPickerItem?

    private let uploadRepository: any UploadRepository = DependencyContainer.current.resolve()

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    init(conversationID: String, initialMessage: String? = nil, initialAttachments: [AIAttachmentPayload] = []) {
        self.conversationID = conversationID
        self.initialMessage = initialMessage
        self.initialAttachments = initialAttachments
        _viewModel = State(initialValue: AIChatViewModel(conversationID: conversationID))
    }

    var body: some View {
        VStack(spacing: 0) {
            AITtsBar()
            messageList
                .opacity(fadedIn ? 1 : 0)
            AIChatInputBar(
                text: $inputText,
                attachments: attachments,
                isBusy: viewModel.isSending,
                isStreaming: viewModel.isStreaming,
                onVoice: VoiceFeature.showVoiceEntryPoint
                    ? { coordinator.presentAIAudioConversation(conversationID: conversationID) }
                    : nil,
                onAttach: { isPhotoPickerPresented = true },
                onRemoveAttachment: { index in
                    if attachments.indices.contains(index) { attachments.remove(at: index) }
                },
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
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            photoSelection = nil
            Task { await attach(item) }
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
                .simultaneousGesture(TapGesture().onEnded { aiDismissKeyboard() })
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
        // `_send`: only fully uploaded attachments go out; the strip clears.
        let uploaded = AIAttachmentStaging.payloads(from: attachments)
        inputText = ""
        attachments = []
        aiDismissKeyboard()
        Task { await viewModel.sendMessage(payload: AISendPayload(message: text, attachments: uploaded)) }
    }

    /// `_pickFile` + `_uploadAttachment`: one image at a time (a new pick
    /// replaces the strip), uploaded straight away through the presigned flow.
    private func attach(_ item: PhotosPickerItem) async {
        guard let staged = await AIAttachmentStaging.stage(item) else {
            toastCenter.show("Something went wrong, please check your network and try again.")
            return
        }
        // `_pickFile`: a new pick replaces the strip.
        attachments = [staged.pending]
        let id = staged.pending.id
        if let key = await AIAttachmentStaging.upload(staged, using: uploadRepository) {
            if let index = attachments.firstIndex(where: { $0.id == id }) {
                attachments[index].isUploading = false
                attachments[index].uploadedKey = key
            }
        } else {
            attachments.removeAll { $0.id == id }
            toastCenter.show("Something went wrong, please check your network and try again.")
        }
    }

    private func sendInitialMessageIfNeeded() async {
        guard !hasSentInitialMessage,
              let initialMessage,
              !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        hasSentInitialMessage = true
        await viewModel.sendMessage(payload: AISendPayload(message: initialMessage, attachments: initialAttachments))
    }
}
