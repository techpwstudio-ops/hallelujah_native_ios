import SwiftUI

/// `SleepTimerBadge` (`lib/widgets/player/sleep_timer_badge.dart`): a pill
/// under the player controls showing time left with a progress ring and a
/// cancel button, present only while a timer is running. Re-reads the clock
/// once a second through `TimelineView` rather than owning a timer of its own.
struct SleepTimerBadge: View {
    let controller: SleepTimerController

    @Environment(\.appTheme) private var theme

    var body: some View {
        if controller.isActive {
            TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { _ in
                pill(remaining: controller.remaining() ?? 0)
            }
            .transition(.opacity)
        }
    }

    private static let refreshInterval: TimeInterval = 1
    private static let ringSize: CGFloat = 28

    private func pill(remaining: TimeInterval) -> some View {
        GlassSurface {
            HStack(spacing: Spacing.sm) {
                ring(remaining: remaining)
                Text(SleepTimerController.label(forRemaining: remaining))
                    .typography(Typography.labelLarge)
                    .foregroundStyle(theme.color(.textPrimary))
                Button { controller.cancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Turn off sleep timer")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func ring(remaining: TimeInterval) -> some View {
        let progress = SleepTimerController.progress(
            remaining: remaining, totalMinutes: controller.selectedMinutes ?? 0
        )
        return ZStack {
            Circle().stroke(theme.color(.border), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(theme.color(.brandPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(.brandPrimary))
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }
}
