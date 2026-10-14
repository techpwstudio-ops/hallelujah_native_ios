import SwiftUI

/// Animated three-dot indicator shown while the AI is generating a response.
/// Ports `AiTypingIndicator` (`lib/views/ai/widgets/ai_typing_indicator.dart`):
/// 900ms loop, each dot offset by 0.33 phase, opacity `0.3 + 0.7 * wave`.
struct AIChatTypingIndicator: View {
    private static let period: TimeInterval = 0.9

    var body: some View {
        TimelineView(.animation) { timeline in
            let base = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (base + Double(index) * 0.33).truncatingRemainder(dividingBy: 1.0)
                    let wave = 1 - abs(2 * phase - 1)
                    let opacity = min(max(0.3 + 0.7 * wave, 0), 1)
                    Circle()
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 6, height: 6)
                        .padding(.horizontal, 2)
                }
            }
        }
    }
}

/// The logo + typing bubble shown while the AI is streaming and no tokens have
/// arrived yet. Ports `AiThinkingBubble`.
struct AIChatThinkingBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(Circle())

            AIChatTypingIndicator()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                    .fill(AIColors.fill)
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
