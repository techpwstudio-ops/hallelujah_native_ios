import SwiftUI
import UIKit

/// T58 — a single row in the AI chat transcript. Dispatches purely on
/// `message.role`; a user row and an assistant row look and behave quite
/// differently, so this isn't one shared bubble shape with the color
/// swapped — see `userRow`/`assistantRow` below.
///
/// `AIToolResultCard(toolResult:)` is built in parallel by another agent —
/// not part of this task — and referenced here by name/signature only,
/// assumed to be a `View` taking a single `toolResult: AIToolResult`
/// argument (matching `AIMessage.toolData: [AIToolResult]?`'s element
/// type). If that agent's actual initializer differs, only the call site
/// inside `assistantRow` below needs to change.
struct AIChatMessageBubble: View {
    let message: AIMessage
    var onRetry: ((String) -> Void)? = nil
    var onCopy: ((String) -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        switch message.role {
        case .user:
            userRow
        case .assistant:
            assistantRow
        }
    }

    // MARK: - User

    private var userRow: some View {
        HStack {
            Spacer(minLength: Spacing.xxl)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(message.content ?? "")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textOnBrand))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(theme.color(.brandPrimary))
                    }

                if message.isError, let onRetry {
                    retryAffordance { onRetry(message.id) }
                }
            }
        }
    }

    // MARK: - Assistant

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            theme.icon(.tabAI)
                .font(.system(size: 16))
                .foregroundStyle(theme.color(.brandPrimary))
                .frame(width: Spacing.xl, height: Spacing.xl)
                .background {
                    Circle().fill(theme.color(.surfaceSecondary))
                }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if message.isStreamingPlaceholder {
                    AIChatTypingIndicator()
                } else {
                    assistantContent

                    ForEach(Array((message.toolData ?? []).enumerated()), id: \.offset) { _, toolResult in
                        AIToolResultCard(toolResult: toolResult)
                    }
                }

                if message.isError {
                    errorRow
                } else if !message.isStreaming, let content = message.content, !content.isEmpty {
                    copyAffordance(content)
                }
            }

            Spacer(minLength: Spacing.xxl)
        }
    }

    @ViewBuilder
    private var assistantContent: some View {
        if let content = message.content, !content.isEmpty {
            HStack(alignment: .bottom, spacing: 2) {
                MarkdownText(markdown: content)
                if message.isStreaming {
                    BlinkingCursor()
                }
            }
        } else if message.isStreaming {
            BlinkingCursor()
        }
    }

    // MARK: - Shared bits

    private var errorRow: some View {
        HStack(spacing: Spacing.xs) {
            theme.icon(.warning)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(.statusError))
            Text(message.content?.isEmpty == false ? message.content! : "Something went wrong.")
                .typography(Typography.bodySmall)
                .foregroundStyle(theme.color(.statusError))

            if let onRetry {
                retryAffordance { onRetry(message.id) }
            }
        }
    }

    private func retryAffordance(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                theme.icon(.retry)
                    .font(.system(size: 12))
                Text("Retry")
                    .typography(Typography.labelMedium)
            }
            .foregroundStyle(theme.color(.statusError))
        }
        .buttonStyle(.plain)
    }

    /// No Share button, no TTS button — text-only copy-to-clipboard is the
    /// entire v1 "done streaming" action row, per this task's own explicit
    /// exclusions.
    private func copyAffordance(_ content: String) -> some View {
        Button {
            UIPasteboard.general.string = content
            onCopy?(content)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                Text("Copy")
                    .typography(Typography.labelSmall)
            }
            .foregroundStyle(theme.color(.textTertiary))
        }
        .buttonStyle(.plain)
    }
}

/// A small blinking text-cursor shown at the end of an in-flight assistant
/// reply. Its own tiny `View` (rather than inlined) since `assistantContent`
/// needs it from two different branches.
private struct BlinkingCursor: View {
    @Environment(\.appTheme) private var theme
    @State private var isVisible = true

    var body: some View {
        Rectangle()
            .fill(theme.color(.textPrimary))
            .frame(width: 2, height: 14)
            .opacity(isVisible ? 1 : 0)
            .animation(
                Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: isVisible
            )
            .onAppear { isVisible = false }
    }
}
