import SwiftUI

/// Ports `HelpSupportDashboardScreen` (`lib/views/support/dashboard.dart`):
/// Dart embeds FAQ/Feedback/Delete Account as three segmented sub-pages on
/// one screen. `AppRoute` already carries a separate case per destination
/// here (`.faqs`/`.feedback`/`.deleteAccount`), so this is just the
/// navigable list that pushes into them — no state beyond the tab index to
/// port, matching Dart's own screen having none either.
struct HelpView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    var body: some View {
        List {
            row(title: "FAQ", icon: Image(systemName: "questionmark.circle")) {
                coordinator.push(.faqs)
            }

            row(title: "Feedback", icon: theme.icon(.mail)) {
                coordinator.push(.feedback)
            }

            // Dart's three tabs don't visually distinguish this one; a red,
            // weightier row here is a small, justified native improvement
            // (not a behavior change) surfacing it as the distinct,
            // consequential action it is.
            row(title: "Delete Account", icon: theme.icon(.trash), tint: theme.color(.statusError)) {
                coordinator.push(.deleteAccount)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.color(.backgroundPrimary))
        .navigationTitle("Help & Support")
    }

    private func row(title: String, icon: Image, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                icon
                    .font(.system(size: 18))
                    .foregroundStyle(tint ?? theme.color(.textPrimary))
                Text(title)
                    .typography(Typography.titleSmall)
                    .foregroundStyle(tint ?? theme.color(.textPrimary))
                Spacer(minLength: 0)
                theme.icon(.chevronForward)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(.textSecondary))
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }
}
