import SwiftUI

/// `SleepTimerBadge` (`lib/widgets/player/sleep_timer_badge.dart`): a centred
/// pill under the transport row, present only while a timer runs, with 20pt
/// below it. Pill: padding L10 T6 B6 R6, white @ 8% fill, 32pt radius, white
/// @ 12% border. Inside: a 28pt progress ring (2pt, track white @ 12%, arc
/// `#9B8FFF`, round caps) around a 14pt moon that pulses 0.6 -> 1.0 over 2 s
/// easeInOut; an 8pt gap; "Sleep timer" (10pt, white @ 54%, 0.3 tracking)
/// over the time left (13pt w600); a 10pt gap; a 28pt white @ 10% cancel
/// circle with a 14pt white @ 54% close glyph. Refreshes every 60 s and
/// expands in/out over 300 ms easeInOut (`AnimatedSize`).
struct SleepTimerBadge: View {
    let controller: SleepTimerController

    @State private var isPulsedDown = false

    private static let refreshInterval: TimeInterval = 60
    private static let ringSize: CGFloat = 28
    private static let smallLabel = TypographyToken(size: 10, weight: .regular, lineHeightMultiple: 1.2, tracking: 0.3)
    private static let timeLabel = TypographyToken(size: 13, weight: .semibold, lineHeightMultiple: 1.2)

    var body: some View {
        VStack(spacing: 0) {
            if controller.isActive {
                TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { _ in
                    pill(remaining: controller.remaining() ?? 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.isActive)
    }

    private func pill(remaining: TimeInterval) -> some View {
        HStack(spacing: 0) {
            ring(remaining: remaining)
            VStack(alignment: .leading, spacing: 0) {
                Text("Sleep timer")
                    .typography(Self.smallLabel)
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.54))
                Text(SleepTimerController.label(forRemaining: remaining))
                    .typography(Self.timeLabel)
                    .foregroundStyle(PlayerStyle.white)
            }
            .padding(.leading, 8)
            Button { controller.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.54))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(PlayerStyle.whiteAlpha(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .accessibilityLabel("Turn off sleep timer")
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 6))
        .background(PlayerStyle.whiteAlpha(0.08), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(PlayerStyle.whiteAlpha(0.12), lineWidth: 1)
        }
    }

    private func ring(remaining: TimeInterval) -> some View {
        let progress = SleepTimerController.progress(
            remaining: remaining, totalMinutes: controller.selectedMinutes ?? 0
        )
        return ZStack {
            Circle().stroke(PlayerStyle.whiteAlpha(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(PlayerStyle.sleepAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "moon.fill")
                .font(.system(size: 12))
                .foregroundStyle(PlayerStyle.white)
                .opacity(isPulsedDown ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isPulsedDown)
        }
        .padding(2)
        .frame(width: Self.ringSize, height: Self.ringSize)
        .onAppear { isPulsedDown = true }
    }
}
