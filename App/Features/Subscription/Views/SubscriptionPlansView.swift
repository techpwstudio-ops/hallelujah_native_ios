import SwiftUI

/// Ports `SubscriptionPlansPage` (`lib/views/subscription/plans_screen.dart`):
/// plan catalogue, tap-to-select cards, and the purchase/restore/cancel
/// action row. Apple/StoreKit rail only — see `SubscriptionPlansViewModel`'s
/// doc comment for what's deliberately out of scope (Razorpay, family-member
/// management).
///
/// Not ported: Dart's `selectedPlan.description?['benefits']` checklist
/// (`plans_screen.dart:172-196`). `SubscriptionPlan.description` decodes as
/// a flat display string, not the structured `{benefits: [...]}` object —
/// a deliberate simplification from when that DTO was first written (no
/// native call site read inside it yet). This view falls back to rendering
/// that flat string as a single paragraph when the server sends one, rather
/// than a per-benefit checklist.
struct SubscriptionPlansView: View {
    @State private var viewModel = SubscriptionPlansViewModel()
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .background(theme.color(.backgroundPrimary))
            .task { await viewModel.load() }
    }

    private var navigationTitle: String {
        viewModel.isPremiumUser ? "Subscription" : "Continue with Ads"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            LoadingStateView()
        case let .failed(message):
            ErrorStateView(title: "Something went wrong", message: message) {
                Task { await viewModel.load() }
            }
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Upgrade to Premium for ad-free worship, high-quality audio, and offline listening.")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let selectedPlan = viewModel.selectedPlan, let description = selectedPlan.description, !description.isEmpty {
                    GlassSurface(.regular, cornerRadius: Radius.lg) {
                        Text(description)
                            .typography(Typography.bodyMedium)
                            .foregroundStyle(theme.color(.textPrimary))
                            .padding(Spacing.md)
                    }
                }

                ForEach(viewModel.plans) { plan in
                    PlanCard(
                        plan: plan,
                        isSelected: viewModel.resolvedSelectedPlanID == plan.id,
                        isCurrentPlan: plan.id == viewModel.subscription?.planId
                    ) {
                        viewModel.selectPlan(plan)
                    }
                }

                if viewModel.isCancelled, let endDate = viewModel.subscription?.endDate {
                    Text("Your Premium benefits will continue until \(endDate.formatted(date: .abbreviated, time: .omitted)). You can re-activate Premium anytime from this page.")
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textSecondary))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                legalLinks

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .typography(Typography.bodySmall)
                        .foregroundStyle(theme.color(.statusError))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if viewModel.isOwner {
                    actionRow
                }
            }
            .padding(Spacing.md)
        }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Spacing.sm) {
            if viewModel.showRestoreButton {
                AppButton.secondary(
                    "Restore",
                    isLoading: viewModel.purchaseStatus == .restoring,
                    width: nil
                ) {
                    Task { await viewModel.restoreTapped() }
                }
            }

            if viewModel.showCancelButton {
                AppButton.secondary("Cancel Plan", width: nil) {
                    switch viewModel.cancelAction {
                    case let .openManageSubscriptions(url):
                        openURL(url)
                    case .unsupported:
                        break
                    }
                }
            }

            if viewModel.showPrimaryButton {
                AppButton(
                    label: viewModel.primaryButtonTitle,
                    action: {
                        switch viewModel.primaryAction {
                        case .purchase:
                            Task { await viewModel.purchaseSelectedPlan() }
                        case let .openManageSubscriptions(url):
                            openURL(url)
                        case .disabled:
                            break
                        }
                    },
                    isLoading: viewModel.purchaseStatus == .purchasing,
                    enabled: viewModel.primaryAction != .disabled
                )
            }
        }
    }

    private var legalLinks: some View {
        VStack(spacing: Spacing.xs) {
            Text(
                "Payment will be charged to your Apple ID account at confirmation of purchase. " +
                    "Subscription automatically renews unless canceled at least 24 hours before the end of the current period. " +
                    "Your account will be charged for renewal within 24 hours prior to the end of the current period."
            )
            .typography(Typography.bodySmall)
            .foregroundStyle(theme.color(.textSecondary))
            .multilineTextAlignment(.center)

            HStack(spacing: Spacing.xs) {
                Link("Terms of Use", destination: AppConfiguration.current.termsAndConditionsURL)
                Text("|").foregroundStyle(theme.color(.textTertiary))
                Link("Privacy Policy", destination: AppConfiguration.current.privacyPolicyURL)
            }
            .typography(Typography.bodySmall)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One plan card: gradient-free native equivalent of Dart's
/// `AnimatedContainer` selection ring (`plans_screen.dart:198-448`) — a
/// bordered `GlassSurface` that highlights on selection, rather than a
/// pixel-identical port of the custom shadow/ring/gradient treatment there.
private struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let isCurrentPlan: Bool
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    private var isIndividual: Bool { plan.maxMembers <= 1 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Label {
                        Text(plan.name)
                            .typography(Typography.labelSmall)
                    } icon: {
                        Image(systemName: isIndividual ? "person.fill" : "person.2.fill")
                    }
                    .foregroundStyle(theme.color(.textSecondary))

                    Spacer()

                    if isCurrentPlan {
                        Text("Current Plan")
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.textSecondary))
                    }
                }

                Text(isIndividual ? "Music just for you" : "Music for your family")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textSecondary))

                HStack(alignment: .firstTextBaseline) {
                    if let price = plan.price {
                        Text(priceText(price))
                            .typography(Typography.headlineMedium)
                            .foregroundStyle(theme.color(.textPrimary))
                    } else {
                        Text(plan.name)
                            .typography(Typography.headlineMedium)
                            .foregroundStyle(theme.color(.textPrimary))
                    }

                    Spacer()

                    if plan.maxMembers > 1 {
                        Text("Up to \(plan.maxMembers) members")
                            .typography(Typography.labelSmall)
                            .foregroundStyle(theme.color(.textSecondary))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background {
                                Capsule().fill(theme.color(.surfaceSecondary))
                            }
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.color(.textPrimary))
                    }
                }
            }
            .padding(Spacing.md)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.color(.surfacePrimary))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? theme.color(.textPrimary) : .clear, lineWidth: 2)
        }
    }

    private func priceText(_ price: Double) -> String {
        let currency = plan.currency ?? ""
        return "\(currency) \(price.formatted(.number.precision(.fractionLength(0...2)))) / \(plan.billingCycle == .yearly ? "Year" : "Month")"
    }
}
