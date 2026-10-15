import SwiftUI

/// Frosted playback bar shown under the AI page app bar while a reply is read
/// aloud. Ports `AiTtsBar` (`lib/views/ai/widgets/ai_tts_bar.dart`).
struct AITtsBar: View {
    @State private var speaker = AIMessageSpeaker.shared
    @State private var dragValue: Double?

    var body: some View {
        if speaker.isVisible {
            bar
        }
    }

    private var bar: some View {
        let value = min(max(dragValue ?? speaker.progress, 0), 1)
        return HStack(spacing: 0) {
            Button {
                speaker.togglePlayPause()
            } label: {
                playPauseIcon
            }
            .buttonStyle(.plain)
            .disabled(speaker.isBuffering)

            Slider(
                value: Binding(
                    get: { value },
                    set: { dragValue = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing, let finished = dragValue {
                        speaker.seek(toFraction: finished)
                        dragValue = nil
                    }
                }
            )
            .tint(Color.white)
            .disabled(!speaker.canSeek)
            .frame(height: 28)

            Button {
                speaker.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AIColors.white70)
                    .padding(Dimens.spacing8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Dimens.spacing6)
        .glassCapsule(.regular, interactive: true)
        .padding(.top, Dimens.spacing8)
        .padding(.bottom, Dimens.spacing4)
        .padding(.horizontal, Dimens.spacing12)
    }

    @ViewBuilder
    private var playPauseIcon: some View {
        if speaker.isBuffering {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.white)
                .frame(width: Dimens.spacing24, height: Dimens.spacing24)
                .padding(Dimens.spacing8)
        } else if speaker.isTransportPlaying {
            Image(systemName: "pause.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.white)
                .frame(width: Dimens.spacing24, height: Dimens.spacing24)
                .padding(Dimens.spacing8)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.white)
                .frame(width: Dimens.spacing24, height: Dimens.spacing24)
                .padding(.leading, Dimens.spacing2)
                .padding(Dimens.spacing8)
        }
    }
}
