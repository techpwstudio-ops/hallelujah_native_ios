import SwiftUI

/// T60 — "Ask Emet about this verse". Ports the Flutter app's
/// `showAiVerseInsightDialog`/`_AiVerseInsightDialog`
/// (`lib/dialogs/ai_verse_insight_dialog.dart`): a branded header, a
/// "selection card" showing the reference + selected text, a scrollable
/// markdown answer area with loading → streamed → error/retry states, and a
/// Close/"Continue in Emet" action pair.
///
/// Presented as a `.sheet(item:)` from `ReaderView`, the same convention
/// `VerseNoteEditorSheet.swift` uses for anything needing real toolbar
/// chrome (`AppSheetContainer` has no toolbar slot — see that file's own
/// doc comment) rather than Flutter's bespoke centered `showAppDialog`,
/// which has no equivalent component in this codebase. `NavigationTitle` +
/// leading/trailing toolbar buttons stand in for Flutter's custom gradient
/// header and footer row.
///
/// Takes a pre-built `VerseInsightTarget` (T56 widened this from a bare
/// `BibleVerse` + `bookName`/`languageName`, once a second source —
/// `VerseOfDay`, via `VerseInsightTarget.fromVerseOfDay`, not just
/// `BibleVerse` via `.fromBibleVerse` — needed this same dialog). Each
/// call site builds its own target from whatever it already has in hand,
/// mirroring how Flutter's own `showAiVerseInsightDialog` takes a
/// `VerseInsightTarget` too, rather than a `BibleVerse`.
struct AIVerseInsightDialogView: View {
    let target: VerseInsightTarget

    /// Always empty at both current call sites (`VerseRowView`'s whole-row
    /// `.contextMenu`, and the verse-of-day options sheet's "Ask Emet" row —
    /// see `VerseInsightRequest.selectedText`'s own doc comment for why).
    /// Kept as a real parameter, not hardcoded, so a future selection-aware
    /// caller can pass real selected text without this view changing at all.
    var selectedText: String = ""

    @State private var viewModel = VerseInsightViewModel()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private var request: VerseInsightRequest {
        VerseInsightRequest.fromTarget(target, selectedText: selectedText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    selectionCard
                    answerArea
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundPrimary))
            .navigationTitle("Emet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Continue in Emet") {
                        guard let conversationID = viewModel.conversationID else { return }
                        dismiss()
                        coordinator.push(.aiChat(conversationID: conversationID, initialMessage: nil))
                    }
                    .disabled(viewModel.conversationID == nil)
                }
            }
            .task {
                await viewModel.ask(request)
            }
        }
    }

    // MARK: - Selection card

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(request.reference)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer()
                Text(request.language)
                    .typography(Typography.labelSmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(theme.color(.surfaceInput))
                    }
            }
            if !request.isWholeVerse {
                Text("\u{201C}\(request.selectedText)\u{201D}")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .italic()
                    .lineLimit(3)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.color(.surfaceSecondary))
        }
    }

    // MARK: - Answer

    @ViewBuilder
    private var answerArea: some View {
        // The conversation never got off the ground.
        if let askError = viewModel.askError {
            ErrorStateView(
                title: "Couldn't reach Emet",
                message: askError,
                onRetry: { Task { await viewModel.retry(request) } }
            )
        } else if let chatViewModel = viewModel.chatViewModel {
            answerContent(for: chatViewModel)
        } else {
            LoadingStateView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder
    private func answerContent(for chatViewModel: AIChatViewModel) -> some View {
        if let answer = firstAssistantMessage(in: chatViewModel.messages) {
            if answer.isError {
                ErrorStateView(
                    title: "Couldn't get a reply",
                    message: answer.content ?? "Something went wrong. Please try again.",
                    onRetry: { Task { await chatViewModel.retry(messageID: answer.id) } }
                )
            } else if let content = answer.content, !content.isEmpty {
                MarkdownText(markdown: content)
            } else {
                LoadingStateView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        } else {
            LoadingStateView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    /// Port of Flutter's `_answerIndex`: `messages` is newest-first (see
    /// `AIChatViewModel`'s own doc comment), so the first assistant-role row
    /// scanning from the front is the reply to this dialog's own question.
    private func firstAssistantMessage(in messages: [AIMessage]) -> AIMessage? {
        messages.first { $0.role == .assistant }
    }
}
