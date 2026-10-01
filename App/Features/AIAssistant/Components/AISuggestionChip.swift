import SwiftUI

/// T58 — one tappable suggestion chip in the AI chat empty state (backed by
/// `AISuggestionsViewModel`/`GET /ai/suggestions`). A small, roughly-160pt
/// card: a subtle icon plus the suggestion's own text, calling `action` on
/// tap so the call site decides what happens (typically: send this text as
/// the first message in a new/current conversation).
///
/// `.tabAI` (`IconToken.swift`'s `"sparkles"` SF Symbol) doubles as the
/// "subtle sparkle" glyph here — it's the closest existing token to a
/// sparkle/star mark, and reusing it keeps this from adding a new case to an
/// enum this task is expressly forbidden from touching.
struct AISuggestionChip: View {
    let suggestion: AISuggestion
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    private static let width: CGFloat = 160

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                theme.icon(.tabAI)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.color(.brandPrimary))
                Text(suggestion.text)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textPrimary))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding(Spacing.sm)
            .frame(width: Self.width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.color(.surfacePrimary))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: 1)
        }
    }
}
