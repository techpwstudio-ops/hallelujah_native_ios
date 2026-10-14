import Foundation
import Observation

/// Ports `_SubscriptionPlansPageState` (`lib/views/subscription/plans_screen.dart`)
/// — plan catalogue + purchase/restore, Apple/StoreKit rail only (T62 owns
/// Razorpay, T63 owns family-member management).
///
/// `selectedPlanID` mirrors Dart's own invariant exactly, down to its doc
/// comment: "Set only by an explicit tap. Never assigned during build — see
/// [_resolveSelectedId]" (`plans_screen.dart:56-58`). Every other card/CTA
/// derivation below reads `resolvedSelectedPlanID` instead, which — like
/// Dart's `_resolveSelectedId` — is a pure function of `plans`/`membership`,
/// never a stored, written property.
@MainActor
@Observable
final class SubscriptionPlansViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Where the primary CTA sends the user — a purchase, or (for an
    /// Apple-managed subscription that can only be upgraded/reactivated from
    /// the store itself) the App Store's manage-subscriptions screen.
    /// Mirrors `shouldOpenProviderManage`'s branch in Dart's `onPressed`
    /// (`plans_screen.dart:564-577`).
    enum PrimaryAction: Equatable {
        case purchase
        case openManageSubscriptions(URL)
        case disabled
    }

    static let appleManageSubscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    private(set) var plans: [SubscriptionPlan] = []
    private(set) var membership: Membership?
    private(set) var loadState: LoadState = .loading
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    /// Set only by `selectPlan(_:)`. See this type's own doc comment.
    private(set) var selectedPlanID: String?

    var purchaseStatus: StoreKitPurchaseManager.Status { purchaseManager.status }

    private let subscriptionRepository: any SubscriptionRepository
    private let purchaseManager: StoreKitPurchaseManager
    private let membershipStore: MembershipStore
    private let logger = AppLogger(category: .subscription)

    init(container: DependencyContainer = .current) {
        subscriptionRepository = container.resolve()
        purchaseManager = container.resolve()
        membershipStore = container.resolve()
    }

    func load() async {
        membership = await membershipStore.membership
        loadState = .loading
        await fetchPlans()
    }

    /// `ref.read(subscriptionPlanRef.notifier).refreshPlans()`
    /// (`plans_screen.dart:598`, the `RefreshIndicator.onRefresh`).
    func refresh() async {
        isRefreshing = true
        membership = await membershipStore.membership
        await fetchPlans()
        isRefreshing = false
    }

    private func fetchPlans() async {
        do {
            plans = try await subscriptionRepository.fetchPlans()
            loadState = .loaded
        } catch let error as SubscriptionError {
            loadState = .failed(error.message)
        } catch {
            logger.warning("fetch plans failed: \(error)")
            loadState = .failed("Something went wrong. Please try again.")
        }
    }

    /// `GestureDetector.onTap` (`plans_screen.dart:204-209`): a no-op re-tap
    /// of the already-selected plan skips the `setState`.
    func selectPlan(_ plan: SubscriptionPlan) {
        guard selectedPlanID != plan.id else { return }
        selectedPlanID = plan.id
    }

    // MARK: - Derived state — pure, mirrors `plans_screen.dart`'s build-time derivations

    var subscription: Subscription? { membership?.subscription }
    var isPremiumUser: Bool { subscription?.isActive == true }
    var isCancelled: Bool { subscription?.isCanceled == true }
    /// `state.membership?.isOwner != false` (`plans_screen.dart:82`) — a user
    /// with no membership row at all still counts as an owner (there's
    /// nothing to be a family *member* of yet), so the action row stays
    /// visible for a first-time subscriber.
    var isOwner: Bool { membership?.isOwner != false }

    var currentPlan: SubscriptionPlan? { plan(id: subscription?.planId) }
    private var isCurrentPlanFamilyPlan: Bool { (currentPlan?.maxMembers ?? 0) > 1 }

    var resolvedSelectedPlanID: String? {
        if let selectedPlanID, plan(id: selectedPlanID) != nil { return selectedPlanID }

        if isPremiumUser, let subscription {
            if isCancelled {
                // Cancelled but still inside the paid period: default to
                // their OWN plan so the CTA reads "Reactivate" and the order
                // goes out for the plan the backend will actually reactivate
                // (`plans_screen.dart:674-682`).
                if let own = plan(id: subscription.planId) { return own.id }
            } else {
                // Active: default to a genuine upgrade — more members than
                // the current plan, not merely a different plan
                // (`plans_screen.dart:683-692`).
                let currentMaxMembers = currentPlan?.maxMembers ?? subscription.maxMembers
                if let upgrade = plans.first(where: { $0.id != subscription.planId && $0.maxMembers > currentMaxMembers }) {
                    return upgrade.id
                }
            }
        }

        return plans.first?.id
    }

    var selectedPlan: SubscriptionPlan? { plan(id: resolvedSelectedPlanID) }
    var isCurrentSelectedPlan: Bool { resolvedSelectedPlanID == subscription?.planId }

    var isUpgrade: Bool {
        guard let selectedPlan else { return false }
        let baseline = currentPlan?.maxMembers ?? subscription?.maxMembers ?? 0
        return selectedPlan.maxMembers > baseline
    }

    var showRestoreButton: Bool { !isPremiumUser }
    var showCancelButton: Bool { isPremiumUser && !isCancelled && currentPlan != nil }

    /// `!isFamilyPlan || (isCancelled || !isPremiumUser)`
    /// (`plans_screen.dart:544-545`) — hides the primary CTA row entry while
    /// an active (non-cancelled) family-plan owner; managing that family's
    /// members is T63's screen, not this button's.
    var showPrimaryButton: Bool { !isCurrentPlanFamilyPlan || isCancelled || !isPremiumUser }

    private var isStoreManagedProvider: Bool {
        let provider = subscription?.providerName?.uppercased()
        return provider == "APPLE" || provider == "GOOGLE"
    }

    private var shouldOpenProviderManage: Bool {
        isPremiumUser && isStoreManagedProvider && (isUpgrade || (isCancelled && isCurrentSelectedPlan))
    }

    /// `_getButtonText` (`plans_screen.dart:634-650`), ported verbatim.
    var primaryButtonTitle: String {
        guard isPremiumUser else { return selectedPlan?.freeTrial != nil ? "Activate Free Trial" : "Subscribe" }
        if isCancelled {
            if isCurrentSelectedPlan { return "Reactivate" }
            return isUpgrade ? "Upgrade to Family" : "Switch Plan"
        }
        if isUpgrade { return "Upgrade to Family" }
        return isCurrentSelectedPlan ? "Subscribed" : "Switch Plan"
    }

    var primaryAction: PrimaryAction {
        guard selectedPlan != nil else { return .disabled }
        if shouldOpenProviderManage {
            // Only APPLE actually opens anything on this build — a GOOGLE-
            // provider subscription can reach this screen (e.g. a cross-
            // platform account), but this iOS build has no Play Store link
            // to hand it to; Dart's own `_googleManageSubscriptionUrl`
            // branch has no native counterpart here.
            guard subscription?.providerName?.uppercased() == "APPLE" else { return .disabled }
            return .openManageSubscriptions(Self.appleManageSubscriptionURL)
        }
        return .purchase
    }

    private func plan(id: String?) -> SubscriptionPlan? {
        guard let id else { return nil }
        return plans.first { $0.id == id }
    }

    // MARK: - Cancel button (`buildCancelButton`, `plans_screen.dart:605-629`)

    enum CancelAction: Equatable {
        case openManageSubscriptions(URL)
        /// RAZORPAY/`showCancelPlanSheet`: confirm in-app, then
        /// `cancelSubscription()`.
        case showCancelSheet
        /// The GOOGLE branch — no Play Store link on this build.
        case unsupported
    }

    var cancelAction: CancelAction {
        switch subscription?.providerName?.uppercased() {
        case "APPLE": .openManageSubscriptions(Self.appleManageSubscriptionURL)
        case "GOOGLE": .unsupported
        default: .showCancelSheet
        }
    }

    /// `PaymentService.cancel` — `true` once the server accepted it.
    func cancelSubscription() async -> Bool {
        errorMessage = nil
        do {
            if let membership = try await subscriptionRepository.cancelSubscription() {
                await membershipStore.setMembership(membership)
                self.membership = membership
            }
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    // MARK: - Purchase / restore

    func purchaseSelectedPlan() async {
        guard let selectedPlan else { return }
        errorMessage = nil
        do {
            if let membership = try await purchaseManager.purchase(plan: selectedPlan) {
                self.membership = membership
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func restoreTapped() async {
        errorMessage = nil
        do {
            if let membership = try await purchaseManager.restorePurchases() {
                self.membership = membership
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? StoreKitPurchaseManager.PurchaseError { return error.displayMessage }
        if let error = error as? SubscriptionError { return error.message }
        return "Something went wrong. Please try again."
    }
}
