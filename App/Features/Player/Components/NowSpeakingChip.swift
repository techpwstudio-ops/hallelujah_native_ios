import SwiftUI

/// "Now speaking" above the read-along card (Phase 2). It names the speaker of the
/// active word, and its bars pause in silence (`store.clock.isSpeaking`). Shown
/// only with two or more speakers.
struct NowSpeakingChip: View {
    let store: EpisodeTimelineStore

    /// The speaker's name, or the localized "Speaker N" built from its place in the list.
    private var speakerName: String? {
        guard let word = store.clock.activeWordIndex,
              let label = store.index?.speakerLabel(forWord: word),
              let position = store.speakerPosition(forLabel: label) else { return nil }
        let speaker = store.speakers[position]
        return speaker.name ?? String(localized: "Speaker \(position + 1)")
    }

    var body: some View {
        if store.hasMultipleSpeakers, let name = speakerName {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: store.clock.isSpeaking)
                Text("Now speaking")
                    .typography(Typography.labelMedium)
                Text(name)
                    .typography(Typography.labelMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(PlayerStyle.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(PlayerStyle.whiteAlpha(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        }
    }
}
