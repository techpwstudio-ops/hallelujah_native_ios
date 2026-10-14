import Foundation
import Observation

/// T60 — drives `AIVerseInsightDialogView`. Ports the Flutter app's
/// `verseInsightProvider` (`lib/river_pods/verse_insight_provider.dart`),
/// which this task didn't need to read directly — the dialog widget it
/// backs (`lib/dialogs/ai_verse_insight_dialog.dart`) documents its whole
/// contract: `ask(request)` creates a conversation then sends the request's
/// prompt, exposing whatever fails along the way.
///
/// Deliberately *not* `AIChatViewModel` reused directly: that type requires
/// a `conversationID` up front (see its own `init`), and this dialog doesn't
/// have one until `ask(_:)` creates a conversation — so this type owns that
/// first step, then hands off to a freshly constructed `AIChatViewModel` for
/// the actual send/stream/retry machinery T58 already built.
///
/// No conversation title is set at creation — `AIChatRepository
/// .createConversation()` takes no title parameter, unlike what
/// `VerseInsightRequest.title` (ported from Flutter, where
/// `VerseInsightRequest.title` names the Emet history entry) seems to
/// expect. Adding one would be a new backend contract, which this task was
/// scoped to avoid; the resulting conversation shows up in AI history
/// (`AIChatHistoryView`, already built by T58) with the same "New
/// conversation" fallback title any other untitled conversation gets.
@MainActor
@Observable
final class VerseInsightViewModel {
    private(set) var conversationID: String?
    private(set) var chatViewModel: AIChatViewModel?
    private(set) var isAsking = false
    private(set) var askError: String?

    private let repository: any AIChatRepository
    private let container: DependencyContainer
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        self.container = container
        repository = container.resolve()
    }

    /// Creates a fresh conversation, then sends `request.prompt` into it.
    /// `AISendPayload.shouldStream` is `true` whenever `attachments` is
    /// empty (always true here), so this always streams — no explicit flag
    /// needed.
    func ask(_ request: VerseInsightRequest) async {
        guard !isAsking else { return }
        isAsking = true
        askError = nil
        defer { isAsking = false }

        do {
            let conversation = try await repository.createConversation()
            conversationID = conversation.id
            let viewModel = AIChatViewModel(conversationID: conversation.id, container: container)
            chatViewModel = viewModel
            await viewModel.sendMessage(payload: AISendPayload(message: request.prompt, attachments: []))
        } catch let createError {
            logger.warning("verse insight ask failed: \(createError)")
            askError = "Couldn't reach Emet. Please try again."
        }
    }

    /// Mirrors Flutter's `verseInsightProvider.notifier.retry(request)`:
    /// retries the whole ask (fresh conversation, fresh send) only for a
    /// failure at that outer level (`askError != nil`). A failure on the
    /// individual reply *inside* an already-created conversation instead
    /// goes through `AIChatViewModel.retry(messageID:)` directly — the
    /// dialog view calls that itself rather than through this method,
    /// mirroring the Dart dialog's own `chat!.notifier.retry(answer.id)`
    /// call for that case.
    func retry(_ request: VerseInsightRequest) async {
        await ask(request)
    }
}
