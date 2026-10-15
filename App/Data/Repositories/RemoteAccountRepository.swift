import Foundation

/// `session`/`currentUserStore` are the SAME shared instances
/// `RemoteAuthRepository` holds — captured here so a completed deletion
/// notifies through the one real `SignOutSignal` the whole app observes, not
/// an independent teardown path. See `AccountRepository`'s doc comment for
/// why no separate navigation call belongs here.
final class RemoteAccountRepository: AccountRepository {
    fileprivate let client: HTTPClient
    private let session: Session
    fileprivate let currentUserStore: CurrentUserStore

    init(client: HTTPClient, session: Session, currentUserStore: CurrentUserStore) {
        self.client = client
        self.session = session
        self.currentUserStore = currentUserStore
    }

    func deleteAccount(reason: String) async throws -> AccountDeletionResult {
        let response = try await client.send(.deleteAccount(reason: reason))
        let decoded = try? JSONDecoder().decode(DeleteAccountResponseDTO.self, from: response.data)
        // Matches `AuthBloc.delete`'s own fallback: it indexes `body['message']`
        // unconditionally with no null-coalescing, so a message-less body
        // there would hand `showSnackBarToast` a null; this fills that same
        // gap with a generic string instead of propagating an empty toast.
        let message = decoded?.message ?? String(localized: "Something went wrong. Please try again.")

        guard response.statusCode == 200 else {
            return AccountDeletionResult(succeeded: false, message: message)
        }

        await session.logout()
        await currentUserStore.clear()
        return AccountDeletionResult(succeeded: true, message: message)
    }
}

extension RemoteAccountRepository {
    func cancelAccountDeletion() async throws -> AccountDeletionResult {
        let response = try await client.send(.cancelAccountDeletion)
        let decoded = try? JSONDecoder().decode(CancelDeletionResponseDTO.self, from: response.data)
        let message = decoded?.message ?? String(localized: "Something went wrong. Please try again.")
        guard response.statusCode == 200 else {
            return AccountDeletionResult(succeeded: false, message: message)
        }
        if var user = await currentUserStore.user {
            user.deletingDate = nil
            await currentUserStore.setUser(user)
        }
        return AccountDeletionResult(succeeded: true, message: message)
    }
}

private struct CancelDeletionResponseDTO: Decodable {
    let message: String?
}

private struct DeleteAccountResponseDTO: Decodable {
    let message: String?
}
