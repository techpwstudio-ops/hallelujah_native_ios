import Foundation
import Observation

/// Ports `FamilyMembersNotifier` (`lib/river_pods/family_members_provider.dart`)
/// — fetch/refresh plus the local-mutation methods the invite/remove flows
/// below call after a successful round-trip. The Riverpod `onStatusChange`
/// network-reconnect listener (`_listenNetwork`) has no port here: this
/// screen has no equivalent of `InternetService`'s global reachability
/// stream wired to it yet, and a silent background refetch on reconnect is a
/// minor UX nicety, not load-bearing for "add/remove member round-trips" —
/// pull-to-refresh (`refresh()`) already covers the same recovery path.
@MainActor
@Observable
final class ManageFamilyMembersViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var data: FamilyMembers?
    private(set) var loadState: LoadState = .loading
    private(set) var isRefreshing = false
    private(set) var isSendingInvite = false
    private(set) var sendInviteErrorMessage: String?

    private let repository: any FamilyMembersRepository
    private let logger = AppLogger(category: .subscription)

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
    }

    func load() async {
        loadState = .loading
        await fetch()
    }

    /// `ref.read(familyMembersProvider.notifier).refresh()`, the
    /// `RefreshIndicator.onRefresh` call.
    func refresh() async {
        isRefreshing = true
        await fetch()
        isRefreshing = false
    }

    /// Ports both `fetch()` and `refresh()` (Dart): identical bodies except
    /// `refresh()` additionally flips state to `AsyncLoading()` first, which
    /// this view's `isRefreshing` flag (driving `.refreshable`'s own spinner)
    /// already covers without needing a second loading state here.
    private func fetch() async {
        do {
            data = try await repository.fetchMembers()
            loadState = .loaded
        } catch let error as SubscriptionError {
            // "Keep old data" (Dart) when a previous fetch already
            // succeeded; only show the error screen on a true first-load
            // failure.
            loadState = data != nil ? .loaded : .failed(error.message)
        } catch {
            logger.warning("fetch family members failed: \(error)")
            loadState = data != nil ? .loaded : .failed("Something went wrong. Please try again.")
        }
    }

    // MARK: - Add member

    /// `isValidIdentifier` (`ManageFamilyMembersPage.dart`), ported verbatim
    /// — including its India-specific mobile pattern, which is a faithful
    /// port of the reference, not a native judgment call.
    static func isValidIdentifier(_ identifier: String) -> Bool {
        let value = identifier.trimmingCharacters(in: .whitespaces)
        let emailRegex = #"^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$"#
        let mobileRegex = #"^(\+91[\-\s]?)?[6-9]\d{9}$"#
        return value.range(of: emailRegex, options: .regularExpression) != nil
            || value.range(of: mobileRegex, options: .regularExpression) != nil
    }

    /// `ManagePremiumService.sendInvitation`. Returns `true` on a real
    /// success (200) only — unlike Dart, which also closes the sheet on a
    /// 401 "limit reached" response, this keeps the sheet open on every
    /// failure so the error message stays visible and the identifier isn't
    /// lost; a deliberate adaptation, not a missed branch.
    func sendInvitation(identifier: String) async -> Bool {
        isSendingInvite = true
        sendInviteErrorMessage = nil
        defer { isSendingInvite = false }
        do {
            let invite = try await repository.sendInvitation(identifier: identifier)
            if let data { self.data = data.prependingInvite(invite) }
            return true
        } catch let error as SubscriptionError {
            sendInviteErrorMessage = error.message
            return false
        } catch {
            logger.warning("send invitation failed: \(error)")
            sendInviteErrorMessage = "Something went wrong. Please try again."
            return false
        }
    }

    // MARK: - Invite row actions

    /// `ManagePremiumService.resendInvitation`. Returns the toast text to
    /// show, mirroring Dart's `showSnackBarToast(message: res.data['message'])`
    /// on success / `"Something went wrong"` on failure.
    func resendInvitation(_ invite: FamilyInvite) async -> String {
        do {
            let status = try await repository.resendInvitation(inviteId: invite.id)
            if let data { self.data = data.updatingInviteStatus(invite.id, status: status) }
            return "Invite resent."
        } catch let error as SubscriptionError {
            return error.message
        } catch {
            logger.warning("resend invitation failed: \(error)")
            return "Something went wrong. Please try again."
        }
    }

    /// `ManagePremiumService.deleteInvitation`, called after the caller's own
    /// confirmation step (`showCancelInviteConfirmationSheet` in Dart; a
    /// native `.confirmationDialog` at the call site here).
    func cancelInvitation(_ invite: FamilyInvite) async -> String {
        do {
            try await repository.cancelInvitation(inviteId: invite.id)
            if let data { self.data = data.removingInvite(invite.id) }
            return "Invite cancelled."
        } catch let error as SubscriptionError {
            return error.message
        } catch {
            logger.warning("cancel invitation failed: \(error)")
            return "Something went wrong. Please try again."
        }
    }

    // MARK: - Member row actions

    /// `ManagePremiumService.deleteMember`, called after the caller's own
    /// confirmation step (`showRemoveMemberSheet` in Dart; a native
    /// `.confirmationDialog` here). The reference's own `MemberTile.onRemove`
    /// never reaches this method (see `FamilyMembersRepository`'s doc
    /// comment) — this view wires it for real, since a working remove is
    /// this task's own done criterion.
    func removeMember(_ member: FamilyMember) async -> String {
        do {
            try await repository.removeMember(memberId: member.id)
            if let data { self.data = data.removingMember(member.id) }
            return "Member removed."
        } catch let error as SubscriptionError {
            return error.message
        } catch {
            logger.warning("remove member failed: \(error)")
            return "Something went wrong. Please try again."
        }
    }
}
