import SwiftUI

/// A tappable suggestion chip on the AI home screen. Ports `AiSuggestionChip`
/// (`lib/views/ai/widgets/ai_suggestion_chip.dart`): 160pt wide, 10pt padding,
/// `fillColor` card, radius 10, two gold stars above a 2-line body-small label.
struct AISuggestionChip: View {
    let text: String
    let action: () -> Void
    /// Fixed height when hosted in the home row (Flutter's list stretches chips to its cross axis).
    var height: CGFloat? = nil

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AIColors.gold)
                        .offset(x: 0, y: 0)
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AIColors.gold)
                        .offset(x: 10, y: 9)
                }
                .frame(width: 24, height: 18, alignment: .topLeading)

                Text(text)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(width: 160, height: height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AIColors.fill)
            }
        }
        .buttonStyle(.plain)
    }
}
