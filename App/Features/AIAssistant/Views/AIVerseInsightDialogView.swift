import SwiftUI
import UIKit

/// "Ask Emet about this verse". Ports `showAiVerseInsightDialog` /
/// `_AiVerseInsightDialog` (`lib/dialogs/ai_verse_insight_dialog.dart`) drawn
/// the way `showAppDialog` (`lib/dialogs/app_dialog.dart`) frames it: a 65%
/// black scrim with a centred 28pt-radius #111111 panel (max 430pt wide, 22pt
/// side margins, 6% white border, soft shadow) holding
/// - a header: 24pt logo, gradient "Emet" (titleMedium bold) and a close icon,
/// - a selection card (5% white fill, reference + language badge, selected
///   text in italics when a part of the verse was picked),
/// - the answer (spinner → streamed markdown → error text with "Try again"),
///   scrollable up to 42% of the screen height,
/// - a hairline, then a 58pt "Close" | "Continue in Emet" action row.
///
/// Present it with `.fullScreenCover`; it clears the cover's own background so
/// only the scrim and panel show.
struct AIVerseInsightDialogView: View {
    let target: VerseInsightTarget

    /// Always empty at the current call sites (SwiftUI exposes no text
    /// selection range). Kept as a real parameter so a selection-aware caller
    /// can pass the words picked.
    var selectedText: String = ""
    /// Overrides the verse's own language (the reader passes the chapter open).
    var language: String? = nil

    @State private var viewModel = VerseInsightViewModel()

    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationCoordinator.self) private var coordinator

    private var request: VerseInsightRequest {
        VerseInsightRequest.fromTarget(target, selectedText: selectedText, language: language)
    }

    /// `MediaQuery.of(context).size.height * 0.42`.
    private var maxAnswerHeight: CGFloat { UIScreen.main.bounds.height * 0.42 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    selectionCard
                    Spacer().frame(height: Dimens.spacing16)
                    ScrollView {
                        answerArea
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: maxAnswerHeight)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(EdgeInsets(top: Dimens.spacing12, leading: Dimens.spacing20, bottom: Dimens.spacing20, trailing: Dimens.spacing20))

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                actions
            }
            .frame(maxWidth: 430)
            .background(Color(readRGB: 0x111111, opacity: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 30, x: 0, y: 16)
            .padding(.horizontal, 22)
        }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.ask(request)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Spacer().frame(width: Dimens.spacing8)
            AIGradientText(text: "Emet", font: AIColors.font(16, .bold))
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Dimens.spacing20 - 4, weight: .medium))
                    .foregroundStyle(AIColors.white70)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(EdgeInsets(top: Dimens.spacing16, leading: Dimens.spacing20, bottom: 0, trailing: Dimens.spacing8))
    }

    // MARK: - Selection card

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Dimens.spacing8) {
                Text(request.reference)
                    .readText(Typography.bodyMedium, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(request.language)
                    .readText(Typography.bodySmall, color: AIColors.white70)
                    .padding(.horizontal, Dimens.spacing8)
                    .padding(.vertical, Dimens.spacing2)
                    .background(
                        RoundedRectangle(cornerRadius: Dimens.cornerRadiusSmall, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            if !request.isWholeVerse {
                Spacer().frame(height: Dimens.spacing6)
                Text("\u{201C}\(request.selectedText)\u{201D}")
                    .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body).weight(.light).italic())
                    .lineSpacing(14 * 0.25)
                    .foregroundStyle(AIColors.white70)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(Dimens.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Answer

    @ViewBuilder
    private var answerArea: some View {
        // The conversation never got off the ground.
        if let askError = viewModel.askError {
            errorBlock(askError, onRetry: { Task { await viewModel.retry(request) } })
        } else if let chatViewModel = viewModel.chatViewModel {
            answerContent(for: chatViewModel)
        } else {
            spinner
        }
    }

    @ViewBuilder
    private func answerContent(for chatViewModel: AIChatViewModel) -> some View {
        if let answer = firstAssistantMessage(in: chatViewModel.messages) {
            if answer.isError {
                errorBlock(
                    answer.content ?? String(localized: "Something went wrong. Please try again."),
                    onRetry: chatViewModel.canRetry(messageID: answer.id)
                        ? { Task { await chatViewModel.retry(messageID: answer.id) } }
                        : nil
                )
            } else if let content = answer.content, !content.isEmpty {
                MarkdownText(markdown: content)
            } else {
                spinner
            }
        } else {
            spinner
        }
    }

    private var spinner: some View {
        ReadSpinner()
            .frame(maxWidth: .infinity)
            .padding(.vertical, Dimens.spacing32)
    }

    /// `_error`: the message (bodyMedium, white 70%, height 1.45) and a pill
    /// "Try again" button (8% white, 16/8 padding) when a retry is possible.
    private func errorBlock(_ message: String, onRetry: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message)
                .readText(Typography.bodyMedium, color: AIColors.white70)
                .lineSpacing(14 * 0.3)
                .multilineTextAlignment(.leading)
            if let onRetry {
                Spacer().frame(height: Dimens.spacing12)
                Button(action: onRetry) {
                    HStack(spacing: Dimens.spacing6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: Dimens.spacing16))
                            .foregroundStyle(Color.white)
                        Text("Try again")
                            .readText(Typography.bodyMedium, weight: .semibold)
                    }
                    .padding(.horizontal, Dimens.spacing16)
                    .padding(.vertical, Dimens.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Dimens.spacing12)
    }

    /// Port of Flutter's `_answerIndex`: `messages` is newest-first, so the
    /// first assistant-role row from the front is the reply to this question.
    private func firstAssistantMessage(in messages: [AIMessage]) -> AIMessage? {
        messages.first { $0.role == .assistant }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .readText(Typography.titleMedium, weight: .medium, color: AIColors.white70)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)

            Button {
                guard let conversationID = viewModel.conversationID else { return }
                dismiss()
                coordinator.push(.aiChat(conversationID: conversationID, initialMessage: nil))
            } label: {
                Text("Continue in Emet")
                    .readText(
                        Typography.titleMedium,
                        weight: .bold,
                        color: viewModel.conversationID == nil ? Color.white.opacity(0.28) : Color.white
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.conversationID == nil)
        }
        .frame(height: 58)
    }
}
