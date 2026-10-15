import SwiftUI

/// Centered empty-state placeholder. Dart's only equivalent, `Empty`
/// (`lib/widgets/empty.dart`), is centered text with a literal
/// `// TODO: implement build` left in its own source — it never grew past a
/// stub, so there's nothing to port 1:1 here. This builds the complete
/// native version the Dart file's own TODO describes: an optional icon,
/// title, message, and retry-style action, all optional so a call site can
/// use just the title (`Empty`'s actual current behavior) or the full form.
struct EmptyStateView: View {
    var icon: IconToken? = nil
    var title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: Spacing.md) {
            if let icon {
                theme.icon(icon)
                    .font(.system(size: 40))
                    .foregroundStyle(theme.color(.textTertiary))
            }
            Text(L10n.tr(title))
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .multilineTextAlignment(.center)
            if let message {
                Text(L10n.tr(message))
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                AppButton.ghost(actionTitle, width: nil, action: action)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Centered error state with a retry action. No Dart precedent to ground
/// against — errors there are surfaced ad hoc via `showSnackBarToast`
/// (`lib/helpers/show_toast_or_snackbar.dart`), never a dedicated full-state
/// view — so this follows the same shape as `EmptyStateView` for visual
/// consistency across the app's state-view family instead.
struct ErrorStateView: View {
    var title: String
    var message: String? = nil
    var retryTitle: String = String(localized: "Try Again")
    var onRetry: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: Spacing.md) {
            theme.icon(.warning)
                .font(.system(size: 40))
                .foregroundStyle(theme.color(.statusError))
            Text(L10n.tr(title))
                .typography(Typography.titleMedium)
                .foregroundStyle(theme.color(.textPrimary))
                .multilineTextAlignment(.center)
            if let message {
                Text(L10n.tr(message))
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
                    .multilineTextAlignment(.center)
            }
            if let onRetry {
                AppButton.secondary(retryTitle, leadingIcon: .retry, width: nil, action: onRetry)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Centered loading spinner. Matches Dart's `ProgressSpinner`
/// (`lib/widgets/progress_spinner.dart`, `Align` + a `LoadingIndicator`
/// package widget); the native `ProgressView` circular style is the direct
/// system equivalent, so there's no reason to hand-roll a custom spinner
/// animation the way the `loading_indicator` package does for Flutter.
struct LoadingStateView: View {
    var message: String? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(theme.color(.textPrimary))
            if let message {
                Text(L10n.tr(message))
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
