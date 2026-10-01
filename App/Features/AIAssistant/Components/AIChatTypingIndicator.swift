import SwiftUI

/// T58 — the "thinking" indicator shown inside an assistant bubble slot
/// while a stream has started but no content has arrived yet
/// (`AIMessage.isStreamingPlaceholder`: `isStreaming && content == nil`).
/// Three dots, phase-offset opacity pulse — no attempt to match a specific
/// reference timing/curve, per this task's own "no need to match exact
/// timing or curves precisely" scope note.
struct AIChatTypingIndicator: View {
    @Environment(\.appTheme) private var theme
    @State private var isAnimating = false

    private static let dotCount = 3
    private static let dotSize: CGFloat = 6

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                Circle()
                    .fill(theme.color(.textSecondary))
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.vertical, Spacing.xs)
        .onAppear { isAnimating = true }
    }
}
