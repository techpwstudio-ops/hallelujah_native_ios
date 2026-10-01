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
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(labelColor)
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

    private var backgroundColor: Color {
        switch variant {
        case .primary: isDisabled ? theme.color(.textTertiary).opacity(0.4) : theme.color(.textPrimary)
        case .secondary, .ghost: .clear
        }
    }

    private var labelColor: Color {
        switch variant {
        case .primary: isDisabled ? theme.color(.textTertiary) : theme.color(.textInverse)
        case .secondary, .ghost: theme.color(.textSecondary)
        }
    }

    private var borderColor: Color? {
        switch variant {
        case .secondary: theme.color(.border)
        case .primary, .ghost: nil
        }
    }
}
