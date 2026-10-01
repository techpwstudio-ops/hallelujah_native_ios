import SwiftUI

/// Wraps the native `Toggle` with the app's tint, matching every `Switch`
/// usage in `lib/views/settings_screen.dart` (`activeColor: Colors.white`).
/// `textPrimary` is the token that resolves to white in dark mode — same
/// "bold ink" substitution `AppButton`'s primary variant uses, so a toggle's
/// on-state reads consistently with a primary button's fill in both color
/// schemes, not just the one Dart ships.
struct AppToggle: View {
    @Binding var isOn: Bool
    var label: String? = nil
    var enabled: Bool = true

    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let label {
                Toggle(isOn: $isOn) {
                    Text(label)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            } else {
                Toggle(isOn: $isOn) { EmptyView() }
                    .labelsHidden()
            }
        }
        .tint(theme.color(.textPrimary))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
