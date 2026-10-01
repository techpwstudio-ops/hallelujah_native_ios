import SwiftUI

/// T58 — the composer shared between `AIChatHomeView` and `AIChatDetailView`
/// (via `AIChatConversationView`, `Views/AIChatHomeView.swift`). v1 scope
/// cut: text only — no attach button, no mic button (both future work, not
/// this task). A rounded, vertically-growing text field plus one trailing
/// circular button whose glyph/behavior tracks send state:
/// - empty text, not busy → disabled, greyed out
/// - non-empty text, not busy → a send arrow; tapping calls `onSend` with
///   the trimmed text and clears the field
/// - `isSending` (queued, no stream started yet) → a small spinner,
///   non-interactive
/// - `isStreaming` → a stop glyph; tapping calls `onStop`
///
/// No `IconToken` case fits "send"/"stop" (`IconToken.swift` is out of scope
/// to extend for this task, same as every other design-system file this
/// task must not touch); raw `Image(systemName:)` is this codebase's own
/// established fallback for exactly that gap — see `SettingsView.swift`/
/// `AddSongsToPlaylistRow.swift`/`LanguageSelectionViews.swift` for existing
/// precedent of the same pattern.
struct AIChatInputBar: View {
    var isSending: Bool = false
    var isStreaming: Bool = false
    var onSend: (String) -> Void
    var onStop: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.appTheme) private var theme

    private static let buttonDiameter: CGFloat = 36
    private static let maxLines = 5

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTextEmpty: Bool { trimmedText.isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Ask anything…", text: $text, axis: .vertical)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .lineLimit(1...Self.maxLines)
                .focused($isFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(theme.color(.surfaceInput))
                }

            trailingButton
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(theme.color(.backgroundPrimary))
        .animation(MotionCurve.fast, value: isStreaming)
        .animation(MotionCurve.fast, value: isSending)
    }

    private var trailingButton: some View {
        Button(action: handleTap) {
            ZStack {
                Circle().fill(buttonBackground)
                buttonGlyph
            }
            .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
        }
        .buttonStyle(.plain)
        .disabled(isButtonDisabled)
    }

    @ViewBuilder
    private var buttonGlyph: some View {
        if isStreaming {
            Image(systemName: "stop.fill")
                .font(.system(size: 13))
                .foregroundStyle(theme.color(.textInverse))
        } else if isSending {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.color(.textInverse))
                .scaleEffect(0.7)
        } else {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(.textInverse))
        }
    }

    /// `isSending` (queued, pre-stream) is the only state with nothing
    /// useful to do on tap — `isStreaming` still needs to reach `onStop`,
    /// and an empty field's send action simply isn't valid yet.
    private var isButtonDisabled: Bool {
        if isStreaming { return false }
        if isSending { return true }
        return isTextEmpty
    }

    private var buttonBackground: Color {
        isButtonDisabled ? theme.color(.textTertiary).opacity(0.4) : theme.color(.textPrimary)
    }

    private func handleTap() {
        if isStreaming {
            onStop()
            return
        }
        guard !isSending, !isTextEmpty else { return }
        let message = trimmedText
        text = ""
        onSend(message)
    }
}
