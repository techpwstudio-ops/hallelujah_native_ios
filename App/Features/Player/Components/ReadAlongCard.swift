import SwiftUI

/// The read-along card (Phase 2), modelled on `PlayerLyricsPreviewCard`. It shows
/// about three lines of transcript around the word being spoken. Tapping it opens
/// the full transcript. The caller shows it only when rule R1 holds.
struct ReadAlongCard: View {
    let store: EpisodeTimelineStore
    let onOpen: () -> Void

    private static let cardRadius: CGFloat = 20
    private static let wordsBefore = 8
    private static let wordsAfter = 14
    private static let headerToken = TypographyToken(size: 14, weight: .medium, lineHeightMultiple: 1, tracking: 0.5)
    private static let buttonToken = TypographyToken(size: 12, weight: .semibold, lineHeightMultiple: 1, tracking: 0.3)

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                header
                excerpt
                openPill
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [PlayerStyle.whiteAlpha(0.07), PlayerStyle.whiteAlpha(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .strokeBorder(PlayerStyle.whiteAlpha(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        .onAppear { store.clock.clientAppeared() }
        .onDisappear { store.clock.clientDisappeared() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 16))
                .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
            Text("Read along")
                .typography(Self.headerToken)
                .foregroundStyle(PlayerStyle.whiteAlpha(0.6))
        }
    }

    private var excerpt: some View {
        Text(excerptText)
            .typography(PlayerStyle.titleMediumSemibold)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openPill: some View {
        Text("Transcript")
            .typography(Self.buttonToken)
            .foregroundStyle(PlayerStyle.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(PlayerStyle.whiteAlpha(0.12), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    /// The words around the active one, coloured as on the transcript screen.
    private var excerptText: AttributedString {
        guard let file = store.transcript, !file.words.isEmpty else { return AttributedString() }
        let active = min(store.clock.activeWordIndex ?? 0, file.words.count - 1)
        let lower = max(active - Self.wordsBefore, 0)
        let upper = min(active + Self.wordsAfter + 1, file.words.count)
        var text = AttributedString()
        for wordIndex in lower..<upper {
            var piece = AttributedString("\(file.words[wordIndex]) ")
            let isActive = store.clock.activeWordIndex == wordIndex
            let isSpoken = wordIndex < active
            piece.foregroundColor = TranscriptWordColor.color(spoken: isSpoken, active: isActive)
            text += piece
        }
        return text
    }
}
