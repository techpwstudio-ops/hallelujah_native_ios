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

            AITtsScrubber(
                value: value,
                isEnabled: speaker.canSeek,
                onDrag: { dragValue = $0 },
                onCommit: { finished in
                    speaker.seek(toFraction: finished)
                    dragValue = nil
                }
            )
            .padding(.horizontal, Dimens.spacing4)

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

    /// `audio_video_progress_bar` look (`thumbRadius: 6`, 4pt round-capped bar).
    /// The system `Slider` draws an oversized pill thumb on iOS 26, which
    /// swamped this compact bar.
    private struct AITtsScrubber: View {
        let value: Double
        let isEnabled: Bool
        let onDrag: (Double) -> Void
        let onCommit: (Double) -> Void

        private let thumbRadius: CGFloat = 6
        private let trackHeight: CGFloat = 4

        var body: some View {
            GeometryReader { proxy in
                let trackWidth = max(proxy.size.width - thumbRadius * 2, 1)
                let progressX = trackWidth * CGFloat(min(max(value, 0), 1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AIColors.white24)
                        .frame(width: trackWidth, height: trackHeight)
                        .offset(x: thumbRadius)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: progressX, height: trackHeight)
                        .offset(x: thumbRadius)
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                        .offset(x: progressX)
                }
                .frame(height: proxy.size.height, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { onDrag(fraction(for: $0.location.x, trackWidth: trackWidth)) }
                        .onEnded { onCommit(fraction(for: $0.location.x, trackWidth: trackWidth)) }
                )
            }
            .frame(height: 28)
            .opacity(isEnabled ? 1 : 0.5)
            .allowsHitTesting(isEnabled)
        }

        private func fraction(for x: CGFloat, trackWidth: CGFloat) -> Double {
            Double(min(max(x - thumbRadius, 0), trackWidth) / trackWidth)
        }
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
