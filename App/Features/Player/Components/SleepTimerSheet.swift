import SwiftUI

/// `showSleepTimerSheet` (`lib/sheets/song/sleep_timer_sheet.dart`): content
/// padded 20 / 0 / 20 / 8. Header: 44pt accent-tinted (`#9B8FFF` @ 14%)
/// circle holding a 22pt moon, 14pt gap, "Sleep Timer" (18, w700) over a 12pt
/// subtitle (accent when active, else white @ 38%) that cross-fades over
/// 250 ms. Then a 20pt gap and six 56pt-high option rows ("N minutes", 15pt;
/// selected = accent w700 + trailing check-circle, else white w500). While a
/// timer runs, a 16pt gap, a white @ 12% divider and a "Turn Off Timer" row
/// (red-accent, 36pt tinted circle + timer-off glyph) expand in over 280 ms.
/// Picking an option starts the timer and dismisses.
struct SleepTimerSheet: View {
    let controller: SleepTimerController
    let onDismiss: () -> Void

    private static let titleToken = TypographyToken(size: 18, weight: .bold, lineHeightMultiple: 1.2)
    private static let subtitleToken = TypographyToken(size: 12, weight: .regular, lineHeightMultiple: 1.2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 0) {
                ForEach(SleepTimerController.options, id: \.self) { minutes in
                    optionRow(minutes)
                }
            }
            .padding(.top, 20)
            cancelSection
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.28), value: controller.isActive)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.fill")
                .font(.system(size: 20))
                .foregroundStyle(PlayerStyle.sleepAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(PlayerStyle.sleepAccent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep Timer")
                    .typography(Self.titleToken)
                    .foregroundStyle(PlayerStyle.white)
                Text(subtitle)
                    .typography(Self.subtitleToken)
                    .foregroundStyle(controller.isActive ? PlayerStyle.sleepAccent : PlayerStyle.whiteAlpha(0.38))
                    .id(controller.selectedMinutes ?? -1)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.25), value: controller.selectedMinutes)
        }
    }

    private var subtitle: String {
        if let minutes = controller.selectedMinutes {
            return "Active · \(minutes)m selected"
        }
        return "Stops playback after selected time"
    }

    private func optionRow(_ minutes: Int) -> some View {
        let isSelected = controller.selectedMinutes == minutes
        return Button {
            controller.start(minutes: minutes)
            onDismiss()
        } label: {
            HStack {
                Text("\(minutes) minutes")
                    .typography(TypographyToken(size: 15, weight: isSelected ? .bold : .medium, lineHeightMultiple: 1.2))
                    .foregroundStyle(isSelected ? PlayerStyle.sleepAccent : PlayerStyle.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(PlayerStyle.sleepAccent)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cancelSection: some View {
        if controller.isActive {
            VStack(spacing: 0) {
                Spacer().frame(height: 16)
                Rectangle()
                    .fill(PlayerStyle.whiteAlpha(0.12))
                    .frame(height: 1)
                Button {
                    controller.cancel()
                    onDismiss()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "timer")
                            .font(.system(size: 16))
                            .foregroundStyle(PlayerStyle.redAccent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(PlayerStyle.redAccent.opacity(0.12)))
                        Text("Turn Off Timer")
                            .typography(TypographyToken(size: 15, weight: .semibold, lineHeightMultiple: 1.2))
                            .foregroundStyle(PlayerStyle.redAccent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .transition(.opacity)
        }
    }
}
