import Foundation
import Observation

/// Drives `showAccountDeletionSheet` / `showAccountRestoredSheet`
/// (`lib/sheets/account_deletion/*`). Flutter raises the blocking
/// "Deletion Scheduled" sheet after every non-silent data sync (and on a failed
/// one) whenever the signed-in user carries a `deletingDate`
/// (`data_service.dart`). Call `checkPendingDeletion()` from the same points
/// (shell appear, after sync); host the sheets with `.accountDeletionPendingSheets(_:)`.
@MainActor
@Observable
final class AccountDeletionPendingCoordinator {
    enum Stage: Equatable, Identifiable {
        case scheduled(Date)
        case restored

        var id: String { "account-deletion-pending" }
    }

    var stage: Stage?
    private(set) var isWorking = false

    private let accountRepository: any AccountRepository
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        accountRepository = container.resolve()
        currentUserStore = container.resolve()
    }

    /// Presents the scheduled-deletion sheet when the cached user has a
    /// parseable `deletingDate`; no-op when one is already on screen.
    func checkPendingDeletion() async {
        guard stage == nil,
              let raw = await currentUserStore.user?.deletingDate,
              let date = Date.parseFlexibleISO8601(raw) else { return }
        stage = .scheduled(date)
    }

    /// `onCancelDeletion`. Returns a toast text on failure, `nil` on success
    /// (the restored sheet replaces the scheduled one).
    func cancelDeletion() async -> String? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await accountRepository.cancelAccountDeletion()
            if result.succeeded {
                stage = .restored
                return nil
            }
            return result.message
        } catch {
            logger.warning("cancel account deletion failed: \(error)")
            return "Something went wrong, please check your internet"
        }
    }
}
