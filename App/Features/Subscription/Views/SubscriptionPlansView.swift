import SwiftUI

/// Ports `SubscriptionPlansPage` (`lib/views/subscription/plans_screen.dart`)
/// with the Flutter widget tree: Premium app-bar title, `PlansHero`, selectable
/// `PlanOptionCard`s, `PaymentSummaryCard` (not yet subscribed only),
/// expandable store legal copy, a pinned action row (Cancel Plan outline +
/// white CTA pill) and `Terms | Privacy | Restore` footer links.
///
/// Free-trial copy (pill, "Then ₹x / Month", summary rows) is wired through
/// `PlanCopy.trial(for:)` from `SubscriptionPlan.freeTrial`. See
/// `SubscriptionPlansViewModel` for Apple-rail scope.
struct SubscriptionPlansView: View {
    @State private var viewModel = SubscriptionPlansViewModel()
    @Environment(\.openURL) private var openURL
    @State private var showSuccessSheet = false
    @State private var cancelStep: CancelStep?

    /// `showCancelPlanSheet` → `showConfirmCancelSheet` → `showCancelledSheet`.
    fileprivate enum CancelStep: Identifiable {
        case ask, confirm, done
        var id: Self { self }
    }

    var body: some View {
        content
            .parityScaffold()
            .parityNavTitle { PlansAppBarTitle() }
            .task { await viewModel.load() }
            .parityFitSheet(isPresented: $showSuccessSheet, dismissible: false) {
                SubscribedSuccessSheet { showSuccessSheet = false }
            }
            .parityFitSheet(item: $cancelStep) { step in
                cancelSheet(step)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
                .tint(AccountParity.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Text("Something went wrong")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.plans.isEmpty {
                Text("No plans available")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                loadedContent
            }
        }
    }

    private var loadedContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlansHero()
                    Spacer().frame(height: Dimens.spacing24)

                    ForEach(viewModel.plans) { plan in
                        PlanOptionCard(
                            plan: plan,
                            isSelected: viewModel.resolvedSelectedPlanID == plan.id,
                            isCurrent: plan.id == viewModel.subscription?.planId
                        ) {
                            viewModel.selectPlan(plan)
                        }
                        .padding(.bottom, Dimens.verticalSpacing)
                    }

                    if !viewModel.isPremiumUser, let selectedPlan = viewModel.selectedPlan {
                        PaymentSummaryCard(plan: selectedPlan)
                        Spacer().frame(height: Dimens.spacing16)
                    }

                    ParityExpandableText(
                        text: "Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period.",
                        maxLines: 2
                    )

                    if viewModel.isCancelled, let endDate = viewModel.subscription?.endDate {
                        Text("Your Premium benefits will continue until \(Self.dateFormatter.string(from: endDate)).You can re-activate Premium anytime from the subscription page.")
                            .font(AccountParity.font(14, .light))
                            .lineSpacing(7)
                            .foregroundStyle(AccountParity.white70)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Dimens.paddingLarge)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AccountParity.bodySmall)
                            .foregroundStyle(AccountParity.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Dimens.spacing8)
                    }
                    Spacer().frame(height: Dimens.spacing16)
                }
                .padding(.horizontal, Dimens.paddingLarge)
                .padding(.vertical, Dimens.spacing8)
                // Native-only tablet/Mac adaptation (no Flutter counterpart): a
                // readable column, shared by the pinned actions below.
                .readableContentWidth()
            }
            .refreshable { await viewModel.refresh() }

            actions
                .padding(.top, Dimens.spacing8)
                .padding(.horizontal, Dimens.paddingLarge)
                .padding(.bottom, Dimens.spacing4)
                .readableContentWidth()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return formatter
    }()

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            if viewModel.isOwner && (viewModel.showCancelButton || viewModel.showPrimaryButton) {
                HStack(spacing: 0) {
                    if viewModel.showCancelButton {
                        cancelButton
                    }
                    if viewModel.showCancelButton && viewModel.showPrimaryButton {
                        Spacer().frame(width: Dimens.spacing8)
                    }
                    if viewModel.showPrimaryButton {
                        PlansCtaButton(
                            label: viewModel.primaryButtonTitle,
                            isLoading: viewModel.purchaseStatus == .purchasing,
                            enabled: viewModel.primaryAction != .disabled
                        ) {
                            switch viewModel.primaryAction {
                            case .purchase:
                                Task {
                                    let wasPremium = viewModel.isPremiumUser
                                    await viewModel.purchaseSelectedPlan()
                                    // `showSubscribedSuccessSheet()` once the purchase lands.
                                    if !wasPremium && viewModel.isPremiumUser { showSuccessSheet = true }
                                }
                            case let .openManageSubscriptions(url):
                                openURL(url)
                            case .disabled:
                                break
                            }
                        }
                    }
                }
            }
            PlansFooterLinks(
                onTerms: { openURL(AppConfiguration.current.termsAndConditionsURL) },
                onPrivacy: { openURL(AppConfiguration.current.privacyPolicyURL) },
                onRestore: viewModel.isPremiumUser ? nil : { Task { await viewModel.restoreTapped() } }
            )
        }
    }

    private var cancelButton: some View {
        Button {
            switch viewModel.cancelAction {
            case let .openManageSubscriptions(url):
                openURL(url)
            case .showCancelSheet:
                cancelStep = .ask
            case .unsupported:
                break
            }
        } label: {
            Text("Cancel Plan")
                .font(AccountParity.font(14, .medium))
                .tracking(0.1)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity)
                .frame(height: Dimens.buttonHeight)
                .overlay(Capsule().strokeBorder(AccountParity.white24, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cancel sheets

extension SubscriptionPlansView {
    private var endDate: Date { viewModel.subscription?.endDate ?? Date() }

    @ViewBuilder
    fileprivate func cancelSheet(_ step: CancelStep) -> some View {
        switch step {
        case .ask:
            CancelPlanSheet(
                endDate: endDate,
                onKeep: { cancelStep = nil },
                onCancelSubscription: { cancelStep = .confirm }
            )
        case .confirm:
            ConfirmCancelSheet(
                endDate: endDate,
                onKeep: { cancelStep = nil },
                onCancelSubscription: {
                    Task {
                        cancelStep = await viewModel.cancelSubscription() ? .done : nil
                    }
                }
            )
        case .done:
            SubscriptionCancelledSheet(
                endDate: endDate,
                onContinueListening: { cancelStep = nil },
                onReactivate: { cancelStep = nil }
            )
        }
    }
}
