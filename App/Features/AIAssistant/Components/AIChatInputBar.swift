import SwiftUI
import UIKit

/// UI state for a file being (or already) attached to the next message.
/// Ports `PendingAttachment` (`lib/views/ai/widgets/ai_input_bar.dart`).
struct AIPendingAttachment: Identifiable {
    let id: UUID
    var fileName: String
    var thumbnail: UIImage?
    var isUploading: Bool
    var uploadedKey: String?
    var mimeType: String
}

/// The AI composer. Ports `AiInputBar`: a `fillColor` card (radius 12, margin
/// 10/8) holding an optional attachment strip and a row of attach button,
/// multi-line field (1-5 lines) and one right-hand action that is a spinner,
/// stop, send, or mic depending on state.
struct AIChatInputBar: View {
    @Binding var text: String
    var attachments: [AIPendingAttachment] = []
    var isBusy: Bool = false
    var isStreaming: Bool = false
    /// `nil` hides the mic button (Flutter: `VoiceFeature.showVoiceEntryPoint`).
    var onVoice: (() -> Void)? = nil
    var onAttach: (() -> Void)? = nil
    var onRemoveAttachment: ((Int) -> Void)? = nil
    var hintText: LocalizedStringKey = "Ask anything about the Bible..."
    var onSend: () -> Void
    var onStop: () -> Void

    @FocusState private var isFocused: Bool

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        if isBusy { return false }
        if !hasText { return false }
        if attachments.contains(where: { $0.isUploading }) { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                attachmentStrip
            }
            HStack(alignment: .center, spacing: 0) {
                Button {
                    onAttach?()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(isBusy ? AIColors.white24 : AIColors.white70)
                        .frame(width: 22, height: 22)
                        .padding(.bottom, 2)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                TextField(
                    "",
                    text: $text,
                    prompt: Text(hintText).foregroundStyle(AIColors.hint),
                    axis: .vertical
                )
                .font(AIColors.font(14))
                .foregroundStyle(Color.white)
                .tint(Color.white)
                .lineLimit(1...5)
                .focused($isFocused)
                .disabled(isBusy)
                .padding(.leading, 10)
                .padding(.trailing, 10)

                rightButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .glassRounded(20, interactive: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Right action

    @ViewBuilder
    private var rightButton: some View {
        if isBusy && !isStreaming {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.white.opacity(0.54))
                .frame(width: 24, height: 24)
        } else if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
        } else if hasText || !attachments.isEmpty {
            Button {
                if canSend { onSend() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.black : AIColors.white38)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(canSend ? Color.white : AIColors.white24))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        } else if let onVoice {
            Button(action: onVoice) {
                // `assets/icons/voice_pulses.svg` is not bundled natively yet.
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }

    // MARK: - Attachment strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AIColors.darkFill)
                            if let thumbnail = attachment.thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AIColors.white54)
                            }
                            if attachment.isUploading {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black.opacity(0.54))
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color.white)
                            }
                        }
                        .frame(width: 56, height: 56)

                        Button {
                            onRemoveAttachment?(index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.87)))
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .frame(height: 72, alignment: .top)
    }
}
