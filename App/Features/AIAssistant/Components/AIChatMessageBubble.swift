import SwiftUI
import UIKit

/// A single row in the AI chat transcript. Ports `AiMessageBubble`
/// (`lib/views/ai/widgets/ai_message_bubble.dart`): rows are inset 16pt
/// horizontally / 6pt vertically; user messages are right-aligned gold bubbles
/// with a tail, assistant messages are a left-aligned logo + markdown column
/// with a Copy / Speak / Share action row.
struct AIChatMessageBubble: View {
    let message: AIMessage
    /// Non-nil only when the failed turn can actually be re-sent.
    var onRetry: ((String) -> Void)? = nil
    var onCopy: ((String) -> Void)? = nil

    @Environment(\.toastCenter) private var toastCenter

    var body: some View {
        Group {
            switch message.role {
            case .user:
                UserBubble(message: message, onRetry: onRetry, copy: copy)
            case .assistant:
                if message.isStreaming && (message.content ?? "").isEmpty && !message.isError {
                    AIChatThinkingBubble()
                        .padding(.horizontal, -Dimens.screenPadding + 0)
                } else {
                    AssistantBubble(message: message, onRetry: onRetry, copy: copy)
                }
            }
        }
        .padding(.horizontal, Dimens.screenPadding)
        .padding(.vertical, Dimens.spacing6)
    }

    private func copy(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        UIPasteboard.general.string = text
        toastCenter.show("Copied to clipboard")
        onCopy?(text)
    }
}

// MARK: - User

private struct UserBubble: View {
    let message: AIMessage
    let onRetry: ((String) -> Void)?
    let copy: (String?) -> Void

    private static let gold = AIColors.gold

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: 0) {
                if !message.attachments.isEmpty {
                    AIUserAttachmentGrid(attachments: message.attachments)
                        .padding(.bottom, Dimens.spacing6)
                }
                bubble
                if message.isError, let onRetry {
                    AIRetryButton { onRetry(message.id) }
                        .padding(.top, Dimens.spacing8)
                }
            }
            .onLongPressGesture {
                copy(message.content)
            }
        }
    }

    private var hasText: Bool { !(message.content ?? "").isEmpty }

    @ViewBuilder
    private var bubble: some View {
        if hasText || message.isError {
            HStack(spacing: Dimens.spacing6) {
                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .font(AIColors.font(14))
                        .lineSpacing(14 * (1.4 - 1.15))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if message.isError {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(AIColors.white70)
                }
            }
            .padding(.horizontal, Dimens.paddingMedium)
            .padding(.vertical, Dimens.spacing8 + 2)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 14,
                    style: .continuous
                )
                .fill(Self.gold)
            }
            .overlay(alignment: .bottomTrailing) {
                BubbleTail()
                    .fill(Self.gold)
                    .frame(width: 10, height: 10)
                    .offset(x: 6)
            }
        }
    }
}

/// Port of `_BubbleTailPainter` (right-hand variant): triangle with vertices
/// (0,0), (w,0), (0,h).
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Assistant

private struct AssistantBubble: View {
    let message: AIMessage
    let onRetry: ((String) -> Void)?
    let copy: (String?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Dimens.iconSize, height: Dimens.iconSize)
                .clipShape(Circle())
                .padding(8)
            Spacer().frame(width: 10)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((message.toolData ?? []).enumerated()), id: \.offset) { _, tool in
                    AIToolResultCard(toolResult: tool)
                }
                if !message.attachments.isEmpty {
                    AIAssistantImageGrid(attachments: message.attachments)
                        .padding(.bottom, Dimens.spacing8)
                }
                if message.isError {
                    errorRow
                } else if let content = message.content, !content.isEmpty {
                    MarkdownText(markdown: content)
                    if message.isStreaming {
                        AIStreamCursor()
                    }
                }
                if !message.isStreaming && !message.isError {
                    AIActionRow(message: message, copy: copy)
                        .padding(.top, Dimens.spacing12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 48)
        }
    }

    private var errorRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Dimens.spacing6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(AIColors.redAccent)
                    .padding(.top, 1)
                Text((message.content ?? "").isEmpty ? "Failed to respond." : (message.content ?? ""))
                    .typography(Typography.bodySmall)
                    .foregroundStyle(AIColors.white70)
            }
            if let onRetry {
                AIRetryButton { onRetry(message.id) }
                    .padding(.top, Dimens.spacing8)
            }
        }
    }
}

// MARK: - Action row (Copy, Speak, Share)

private struct AIActionRow: View {
    let message: AIMessage
    let copy: (String?) -> Void

    @State private var speaker = AIMessageSpeaker.shared
    @Environment(\.toastCenter) private var toastCenter

    var body: some View {
        let hasContent = !(message.content ?? "").isEmpty
        let isActive = speaker.isActive(for: message.id)
        let isLoading = isActive && speaker.status == .loading

        HStack(spacing: Dimens.spacing16) {
            Button {
                copy(message.content)
            } label: {
                // `assets/icons/copy.svg` stand-in.
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!hasContent)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AIColors.white54)
                    .frame(width: Dimens.spacing20, height: Dimens.spacing20)
            } else {
                Button {
                    speaker.play(messageID: message.id, content: message.content, language: message.language)
                } label: {
                    // `assets/icons/play_loud.svg` stand-in.
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!hasContent)
            }

            if let content = message.content, !content.isEmpty {
                ShareLink(item: content) {
                    // `assets/icons/share.svg` stand-in, tinted `hintColor`.
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(AIColors.hint)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Retry

/// Circular refresh button shown when a message fails. Ports `RetryIconButton`.
struct AIRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AIColors.white70)
                .frame(width: 18, height: 18)
                .padding(Dimens.spacing8)
                .background(Circle().fill(AIColors.darkFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry")
    }
}

// MARK: - Streaming cursor

/// 2x15 white54 bar fading in/out every 530ms. Ports `_StreamCursor`.
private struct AIStreamCursor: View {
    @State private var visible = false

    var body: some View {
        Rectangle()
            .fill(AIColors.white54)
            .frame(width: Dimens.spacing2, height: 15)
            .opacity(visible ? 1 : 0)
            .padding(.top, Dimens.spacing4 - 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    visible = true
                }
            }
    }
}

// MARK: - Attachments

private func aiIsImage(_ attachment: AIAttachment) -> Bool {
    if let mime = attachment.mimeType { return mime.hasPrefix("image/") }
    let ext = (attachment.key as NSString).pathExtension.lowercased()
    return ["jpg", "jpeg", "png", "gif", "webp"].contains(ext)
}

private struct AIAttachmentImage: View {
    let key: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ArtworkView(
            url: ArtworkURLResolver().resolve(path: key, variant: .lg, allowedVariants: nil),
            width: width,
            height: height,
            cornerRadius: 0,
            contentMode: .fill
        )
        .frame(width: width, height: height)
        .clipped()
    }
}

private struct AIImageRow: View {
    let images: [AIAttachment]

    var body: some View {
        Group {
            if images.count == 1, let first = images.first {
                AIAttachmentImage(key: first.key, width: 218, height: 218)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(images.prefix(2).enumerated()), id: \.offset) { _, attachment in
                        AIAttachmentImage(key: attachment.key, width: 110, height: 218)
                            .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous))
    }
}

private struct AIAssistantImageGrid: View {
    let attachments: [AIAttachment]

    var body: some View {
        let images = attachments.filter(aiIsImage)
        if !images.isEmpty {
            AIImageRow(images: images)
        }
    }
}

private struct AIUserAttachmentGrid: View {
    let attachments: [AIAttachment]

    var body: some View {
        let images = attachments.filter(aiIsImage)
        let others = attachments.filter { !aiIsImage($0) }
        VStack(alignment: .trailing, spacing: 0) {
            if !images.isEmpty {
                AIImageRow(images: images)
            }
            ForEach(Array(others.enumerated()), id: \.offset) { _, attachment in
                AIFileCard(attachment: attachment)
            }
        }
    }
}

private struct AIFileCard: View {
    let attachment: AIAttachment

    var body: some View {
        let mime = attachment.mimeType ?? ""
        let symbol = mime.hasPrefix("audio/") ? "music.note" : (mime.hasPrefix("video/") ? "video.fill" : "doc.fill")
        HStack(spacing: Dimens.spacing8) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(AIColors.white54)
            Text((attachment.key as NSString).lastPathComponent)
                .typography(Typography.bodySmall)
                .foregroundStyle(AIColors.white70)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Dimens.spacing8)
        .background {
            RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous).fill(AIColors.darkFill)
        }
        .padding(.top, Dimens.spacing4)
    }
}
