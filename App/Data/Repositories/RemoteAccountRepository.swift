import Foundation

/// `session`/`currentUserStore` are the SAME shared instances
/// `RemoteAuthRepository` holds — captured here so a completed deletion
/// notifies through the one real `SignOutSignal` the whole app observes, not
/// an independent teardown path. See `AccountRepository`'s doc comment for
/// why no separate navigation call belongs here.
final class RemoteAccountRepository: AccountRepository {
    private let client: HTTPClient
    private let session: Session
    private let currentUserStore: CurrentUserStore

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
        let message = decoded?.message ?? "Something went wrong. Please try again."

        guard response.statusCode == 200 else {
            return AccountDeletionResult(succeeded: false, message: message)
        }

        await session.logout()
        await currentUserStore.clear()
        return AccountDeletionResult(succeeded: true, message: message)
    }
}

private struct DeleteAccountResponseDTO: Decodable {
    let message: String?
}
