import SwiftUI

/// The three button treatments ported from `lib/widgets/app_button.dart`'s
/// `AppButtonVariant`.
enum AppButtonVariant: Sendable {
    case primary
    case secondary
    case ghost
}

/// Ported from `AppButton` (`lib/widgets/app_button.dart`): same three
/// variants, same disabled-while-loading behavior (`isDisabled = !enabled ||
/// isLoading`), same default height (`Spacing.buttonHeight`, 48) and radius
/// (`Radius.lg`, matching Dart's `AppSpacing.radiusLg`).
///
/// Color mapping is token-based rather than the Dart literals directly, since
/// this design system supports light mode too (the Flutter app is dark-only):
/// primary's bg/label pair is `textPrimary`/`textInverse` — in dark mode that
/// resolves to exactly Dart's white-bg/black-label (`textPrimary` is white on
/// dark, `textInverse` is its opposite, black), and in light mode it inverts
/// symmetrically (near-black bg, white label) rather than going white-on-white.
/// Secondary's border uses the `border` token, the asset-catalog equivalent of
/// Dart's literal `Colors.white24`.
struct AppButton: View {
    let label: String
    let action: () -> Void
    var isLoading: Bool = false
    var enabled: Bool = true
    var variant: AppButtonVariant = .primary
    var leadingIcon: IconToken? = nil
    var width: CGFloat? = .infinity

    @Environment(\.appTheme) private var theme

    static func secondary(
        _ label: String,
        isLoading: Bool = false,
        enabled: Bool = true,
        leadingIcon: IconToken? = nil,
        width: CGFloat? = .infinity,
        action: @escaping () -> Void
    ) -> AppButton {
        AppButton(
            label: label, action: action, isLoading: isLoading, enabled: enabled,
            variant: .secondary, leadingIcon: leadingIcon, width: width
        )
    }

    static func ghost(
        _ label: String,
        isLoading: Bool = false,
        enabled: Bool = true,
        leadingIcon: IconToken? = nil,
        width: CGFloat? = .infinity,
        action: @escaping () -> Void
    ) -> AppButton {
        AppButton(
            label: label, action: action, isLoading: isLoading, enabled: enabled,
            variant: .ghost, leadingIcon: leadingIcon, width: width
        )
    }

    private var isDisabled: Bool { !enabled || isLoading }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    // `app_button.dart` shows a 24pt Material spinner.
                    MaterialSpinner(color: labelColor, size: 24, lineWidth: 2.5)
                } else {
                    HStack(spacing: Spacing.sm) {
                        if let leadingIcon {
                            theme.icon(leadingIcon)
                        }
                        Text(label)
                            .typography(Typography.titleSmall)
                    }
                }
            }
            .foregroundStyle(labelColor)
            .frame(maxWidth: width)
            .frame(height: Spacing.buttonHeight)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(backgroundColor)
        }
        .overlay {
            if let borderColor {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
        .disabled(isDisabled)
        .animation(MotionCurve.fast, value: isDisabled)
    }

    /// `Colors.grey.shade600`.
    private static let disabledFill = Color(red: 0x75 / 255, green: 0x75 / 255, blue: 0x75 / 255)

    private var backgroundColor: Color {
        switch variant {
        // `app_button.dart`: grey.shade600 when disabled, white otherwise.
        case .primary: isDisabled ? Self.disabledFill : .white
        case .secondary, .ghost: .clear
        }
    }

    private var labelColor: Color {
        switch variant {
        // `app_button.dart`: white54 on the disabled fill, black on white;
        // secondary/ghost labels are white70.
        case .primary: isDisabled ? Color.white.opacity(0.54) : .black
        case .secondary, .ghost: Color.white.opacity(0.7)
        }
    }

    private var borderColor: Color? {
        switch variant {
        case .secondary: Color.white.opacity(0.24)
        case .primary, .ghost: nil
        }
    }
}
