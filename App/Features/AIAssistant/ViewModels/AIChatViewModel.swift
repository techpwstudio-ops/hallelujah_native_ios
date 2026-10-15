import Foundation
import Observation

/// T58 — one per-conversation chat session. Ports the Flutter app's
/// `AiChatNotifier`. Drives a single conversation's transcript: initial
/// load, older-page pagination, sending (streamed or non-streamed), and
/// retrying a failed send.
///
/// `AIChatRepository` (`App/Domain/Repositories/AIChatRepository.swift`)
/// covers the 5 non-streaming routes this view model calls into;
/// `AIChatStreamingClient` (`App/Data/Networking/AIChatStreamingClient.swift`)
/// is the separate SSE client for the 6th (`sendStream(payload:)` below).
@MainActor
@Observable
final class AIChatViewModel {
    let conversationID: String

    /// Newest-first: index 0 is the most recently received row (the
    /// inverted-list ordering a chat transcript's UI wants — new messages
    /// arrive at the top of the backing array, not the bottom). This is the
    /// opposite of the wire's own oldest→newest page order
    /// (`AIChatRepository.getMessages`), so `loadMessages()`/`loadMore()`
    /// each reverse an incoming page before merging it in.
    private(set) var messages: [AIMessage] = []
    private(set) var isInitialLoading = true
    private(set) var isLoadingMore = false
    private(set) var isSending = false
    private(set) var isStreaming = false
    private(set) var hasMore = false
    /// See `AIChatDTOs.swift`'s `AICursorPageDTO.toPaginated(_:)` doc
    /// comment: `AIChatRepository`'s return type is `Paginated<T>`, which
    /// has no cursor field, so a real wire `nextCursor` can never actually
    /// reach this property under the current Data layer — it stays `nil`
    /// after every fetch. `loadMore()` still threads it through
    /// `getMessages(conversationID:cursor:)` as specified, and dedupes by
    /// message id when appending so that re-fetching the same page (the
    /// practical effect of always passing `cursor: nil`) can't insert
    /// duplicate `Identifiable` rows into the transcript.
    private(set) var nextCursor: String?
    private(set) var error: String?

    var isBusy: Bool { isSending || isStreaming }

    private let repository: any AIChatRepository
    private let streamingClient: AIChatStreamingClient
    private let logger = AppLogger(category: .content)

    /// The in-flight `sendStream(payload:)` task, held so `cancelStream()`
    /// has something to cancel — `AIChatStreamingClient` exposes an
    /// `AsyncThrowingStream`, not a cancellable token of its own.
    private var streamTask: Task<Void, Never>?

    init(conversationID: String, container: DependencyContainer = .current) {
        self.conversationID = conversationID
        repository = container.resolve()
        streamingClient = container.resolve()
    }

    func loadMessages() async {
        isInitialLoading = true
        error = nil
        do {
            let page = try await repository.getMessages(conversationID: conversationID, cursor: nil)
            messages = Array(page.items.reversed())
            hasMore = page.hasMore
            nextCursor = page.nextCursor
            isInitialLoading = false
        } catch let loadError {
            logger.warning("load messages for conversation \(conversationID) failed: \(loadError)")
            let message = AIErrorParser.parse(loadError)
            error = message.isEmpty ? nil : message
            isInitialLoading = false
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.getMessages(conversationID: conversationID, cursor: nextCursor)
            let existingIDs = Set(messages.map(\.id))
            let olderMessages = page.items.reversed().filter { !existingIDs.contains($0.id) }
            messages.append(contentsOf: olderMessages)
            hasMore = page.hasMore
            nextCursor = page.nextCursor
        } catch let loadMoreError {
            logger.warning("load more messages for conversation \(conversationID) failed: \(loadMoreError)")
            let message = AIErrorParser.parse(loadMoreError)
            error = message.isEmpty ? nil : message
            // Existing rows are left untouched — `hasMore`/`messages` both
            // keep their pre-failure values, so the view's own retry
            // affordance (calling `loadMore()` again) has something
            // meaningful to retry against.
        }
    }

    /// Optimistically inserts a local `user` row, then hands off to the
    /// streamed or non-streamed send path per `payload.shouldStream`.
    func sendMessage(payload: AISendPayload) async {
        guard !isBusy else { return }
        error = nil

        let localMessage = AIMessage.localUser(
            id: UUID().uuidString,
            content: payload.message,
            attachments: payload.attachments.map { AIAttachment(key: $0.key, mimeType: $0.mimeType) }
        )
        messages.insert(localMessage, at: 0)

        if payload.shouldStream {
            await sendStream(payload: payload)
        } else {
            await sendFull(payload: payload)
        }
    }

    /// Re-sends a previously failed turn. `messages` is newest-first, so the
    /// "source" user message behind a given errored row is either the row
    /// itself (`sendFull`'s failure path leaves the failed row as the user
    /// message it always was) or the next-older row (`sendStream`'s failure
    /// path replaces its *assistant* placeholder with the error row, one
    /// slot ahead of the user message that triggered it — see
    /// `finalizeStreamError(placeholderID:message:)`).
    func retry(messageID: String) async {
        guard let erroredIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let erroredMessage = messages[erroredIndex]

        let sourceIndex = erroredMessage.role == .user ? erroredIndex : erroredIndex + 1
        guard sourceIndex < messages.count else { return }
        let source = messages[sourceIndex]

        guard let payload = Self.payload(for: source) else { return }

        // Remove the failed pair before resending — `sendMessage(payload:)`
        // below inserts a fresh optimistic pair of its own. Removing the
        // higher index first keeps the lower index valid.
        if sourceIndex == erroredIndex {
            messages.remove(at: erroredIndex)
        } else {
            messages.remove(at: max(sourceIndex, erroredIndex))
            messages.remove(at: min(sourceIndex, erroredIndex))
        }

        await sendMessage(payload: payload)
    }

    /// Cancels the in-flight stream. Cancellation is cooperative: this only
    /// flips `streamTask`'s cancelled flag — `sendStream(payload:)`'s own
    /// task body is what notices (its network call throws once cancelled)
    /// and finalizes the placeholder with whatever partial content had
    /// already accumulated, via `finalizeStreamPartial(placeholderID:)`.
    func cancelStream() {
        streamTask?.cancel()
    }

    /// Whether the errored message can be retried: nothing in flight and a
    /// re-sendable user message behind it. Ports `AiChatState.canRetryAt`.
    func canRetry(messageID: String) -> Bool {
        if isBusy { return false }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return false }
        let message = messages[index]
        guard message.isError else { return false }
        let source: AIMessage?
        if message.role == .user {
            source = message
        } else {
            source = index + 1 < messages.count ? messages[index + 1] : nil
        }
        guard let source else { return false }
        return Self.payload(for: source) != nil
    }

    /// `AiChatNotifier.payloadFor`: rebuilds a send payload from a user message,
    /// or nil when nothing re-sendable is left (e.g. a failed voice upload).
    static func payload(for message: AIMessage) -> AISendPayload? {
        guard message.role == .user else { return nil }
        let text = message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = message.attachments.compactMap { attachment in
            attachment.mimeType.map { AIAttachmentPayload(key: attachment.key, mimeType: $0) }
        }
        let hasText = !(text ?? "").isEmpty
        guard hasText || !attachments.isEmpty else { return nil }
        return AISendPayload(message: hasText ? text : nil, attachments: attachments)
    }

    // MARK: - Send (non-streaming)

    private func sendFull(payload: AISendPayload) async {
        isSending = true
        do {
            let result = try await repository.sendMessage(conversationID: conversationID, payload: payload)
            if !messages.isEmpty {
                messages.removeFirst()
            }
            // Newest-first: insert the confirmed user echo first, then the
            // AI reply, so the AI reply ends up at index 0 — the newest,
            // topmost row — once both are confirmed.
            messages.insert(result.userMessage, at: 0)
            messages.insert(result.aiMessage, at: 0)
            isSending = false
        } catch let sendError {
            if !messages.isEmpty {
                messages[0].isError = true
            }
            isSending = false
            logger.warning("send message in conversation \(conversationID) failed: \(sendError)")
            let message = AIErrorParser.parse(sendError)
            error = message.isEmpty ? nil : message
        }
    }

    // MARK: - Send (streaming)

    // T58 v1 deliberately has no broadcast "reply outcome" stream (the
    // Flutter app's `AiReplyOutcome`/`replyOutcomes`) — nothing consumes one
    // yet, so the published properties below are driven directly instead. A
    // future voice feature will likely need an outcome signal added here.

    private func sendStream(payload: AISendPayload) async {
        let placeholder = AIMessage.streamingPlaceholder()
        messages.insert(placeholder, at: 0)
        isStreaming = true

        let task = Task {
            var buffer = ""
            do {
                let stream = streamingClient.streamMessage(conversationID: conversationID, payload: payload)
                for try await event in stream {
                    switch event {
                    case .delta(let text):
                        buffer += text
                        let parsed = AIMessage.parseRawContent(raw: buffer)
                        applyDelta(placeholderID: placeholder.id, content: parsed.content, toolData: parsed.toolData)
                    case .done(let finalMessage):
                        finalizeStream(placeholderID: placeholder.id, with: finalMessage)
                        return
                    case .cancelled(let finalMessage):
                        finalizeStream(placeholderID: placeholder.id, with: finalMessage)
                        return
                    case .error(let message):
                        finalizeStreamError(placeholderID: placeholder.id, message: message)
                        return
                    }
                }
                // Stream ended without a terminal event at all — defensive
                // backstop so the placeholder doesn't spin forever.
                finalizeStreamPartial(placeholderID: placeholder.id)
            } catch {
                if Task.isCancelled {
                    // `cancelStream()` was called: the underlying network
                    // call throws once its task is cancelled. Keep whatever
                    // partial content already landed on the placeholder via
                    // `applyDelta` rather than discarding it.
                    finalizeStreamPartial(placeholderID: placeholder.id)
                } else {
                    logger.warning("stream message in conversation \(conversationID) failed: \(error)")
                    let message = AIErrorParser.parse(error)
                    finalizeStreamError(
                        placeholderID: placeholder.id,
                        message: message.isEmpty ? "Something went wrong. Please try again." : message
                    )
                }
            }
        }
        streamTask = task
        await task.value
    }

    /// Re-parses the growing raw buffer on every delta through the same
    /// shared `AIMessage.parseRawContent(raw:)` the DTO decode path uses,
    /// then mutates the placeholder row in place by id — no `copyWith`.
    private func applyDelta(placeholderID: String, content: String?, toolData: [AIToolResult]?) {
        guard let index = messages.firstIndex(where: { $0.id == placeholderID }) else { return }
        messages[index].content = content
        messages[index].toolData = toolData
    }

    /// `.done`/`.cancelled` both carry the server's own finalized message
    /// (a real id, `isStreaming` already `false` off `AIMessageDTO.toDomain()`)
    /// — this just swaps it in for the placeholder.
    private func finalizeStream(placeholderID: String, with finalMessage: AIMessage) {
        var message = finalMessage
        message.isStreaming = false
        replacePlaceholder(id: placeholderID, with: message)
        isStreaming = false
    }

    private func finalizeStreamError(placeholderID: String, message errorText: String) {
        let errorMessage = AIMessage(
            id: placeholderID,
            role: .assistant,
            content: errorText,
            toolData: nil,
            attachments: [],
            createdAt: Date(),
            isStreaming: false,
            isError: true,
            language: nil
        )
        replacePlaceholder(id: placeholderID, with: errorMessage)
        isStreaming = false
        error = errorText
    }

    /// Cancellation, or a stream that ended with no terminal event: keeps
    /// the placeholder's row (and whatever partial content `applyDelta`
    /// already wrote into it) as a finished, non-streaming, non-error
    /// message — a cancelled reply stays visible as a partial answer, never
    /// deleted.
    private func finalizeStreamPartial(placeholderID: String) {
        if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
            messages[index].isStreaming = false
        }
        isStreaming = false
    }

    private func replacePlaceholder(id: String, with message: AIMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            // Defensive — the placeholder should always still be present;
            // if it somehow isn't, still surface the finalized row rather
            // than silently dropping it.
            messages.insert(message, at: 0)
            return
        }
        messages[index] = message
    }
}
