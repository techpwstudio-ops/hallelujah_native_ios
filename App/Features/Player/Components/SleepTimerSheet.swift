import SwiftUI

/// `showSleepTimerSheet` (`lib/sheets/song/sleep_timer_sheet.dart`): the six
/// fixed durations, the active one highlighted, and a cancel row while a timer
/// is running. Picking an option starts the timer and dismisses the sheet.
struct SleepTimerSheet: View {
    let controller: SleepTimerController
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        AppSheetContainer {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                ForEach(SleepTimerController.options, id: \.self) { minutes in
                    optionRow(minutes)
                }
                if controller.isActive {
                    cancelRow
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22))
                .foregroundStyle(theme.color(.brandPrimary))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep Timer")
                    .typography(Typography.titleLarge)
                    .foregroundStyle(theme.color(.textPrimary))
                Text(subtitle)
                    .typography(Typography.bodySmall)
                    .foregroundStyle(controller.isActive ? theme.color(.brandPrimary) : theme.color(.textTertiary))
            }
        }
    }

    private var subtitle: LocalizedStringKey {
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
                    .typography(Typography.bodyLarge)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.color(.brandPrimary))
                }
            }
            .frame(minHeight: Spacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cancelRow: some View {
        Button {
            controller.cancel()
            onDismiss()
        } label: {
            Text("Turn off timer")
                .typography(Typography.labelLarge)
                .foregroundStyle(theme.color(.statusError))
                .frame(maxWidth: .infinity, minHeight: Spacing.minTapTarget)
        }
        .buttonStyle(.plain)
    }
}
