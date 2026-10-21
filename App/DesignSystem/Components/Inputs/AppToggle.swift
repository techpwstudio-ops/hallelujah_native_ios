import SwiftUI

/// Matches every `Switch` usage in `lib/views/settings_screen.dart`
/// (`activeColor: Colors.white`). `textPrimary` is the token that resolves to
/// white in dark mode — same "bold ink" substitution `AppButton`'s primary
/// variant uses, so a toggle's on-state reads consistently with a primary
/// button's fill in both color schemes, not just the one Dart ships.
///
/// Drawn by `AppToggleStyle` rather than `.tint` on the native switch: the
/// system knob is always white, so a white tint swallowed it entirely and the
/// on-state rendered as a blank pill.
struct AppToggle: View {
    @Binding var isOn: Bool
    var label: String? = nil
    var enabled: Bool = true

    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let label {
                Toggle(isOn: $isOn) {
                    Text(L10n.tr(label))
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textPrimary))
                }
            } else {
                Toggle(isOn: $isOn) { EmptyView() }
            }
        }
        .toggleStyle(AppToggleStyle(
            hasLabel: label != nil,
            ink: theme.color(.textPrimary),
            inverse: theme.color(.textInverse)
        ))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// On: ink track with an inverse knob (white/black in dark mode, flipped in
/// light). Off: faint ink track with an ink knob. Native switch geometry
/// (51×31, 2pt knob inset) so it sits in rows exactly where `Toggle` did.
/// Unlabeled toggles hug the switch so trailing slots (`ParityListTile`)
/// keep it pinned to the edge instead of splitting the row's free space.
private struct AppToggleStyle: ToggleStyle {
    let hasLabel: Bool
    let ink: Color
    let inverse: Color

    private static let size = CGSize(width: 51, height: 31)
    private static let inset: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.sm) {
            if hasLabel {
                configuration.label
                Spacer(minLength: 0)
            }
            Button {
                configuration.isOn.toggle()
            } label: {
                track(isOn: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
        .accessibilityAction { configuration.isOn.toggle() }
    }

    private func track(isOn: Bool) -> some View {
        let knob = Self.size.height - Self.inset * 2
        return Capsule()
            .fill(isOn ? ink : ink.opacity(0.2))
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? inverse : ink)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .padding(Self.inset)
            }
            .contentShape(Capsule())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
    }
}
