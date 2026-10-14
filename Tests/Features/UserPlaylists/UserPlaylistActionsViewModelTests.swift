import Foundation
import Testing
@testable import GHallelujah

@MainActor
struct UserPlaylistActionsViewModelTests {
    private func makeViewModel(
        repository: FakeUserPlaylistRepository,
        library: FakeLibraryRepository = FakeLibraryRepository()
    ) -> UserPlaylistActionsViewModel {
        UserPlaylistActionsViewModel(
            playlistID: "p1",
            repository: repository,
            libraryRepository: library,
            shareLink: { id in URL(string: "https://example.com/\(id)")! }
        )
    }

    @Test func visibilityToastsMatchDart() async {
        let repository = FakeUserPlaylistRepository()
        repository.visibilityResult = .success(FakeUserPlaylistRepository.playlist(visibility: "public"))
        let viewModel = makeViewModel(repository: repository)
        #expect(await viewModel.toggleVisibility() == "Playlist is now public")
        #expect(viewModel.visibilityTitle == "Make Private")

        repository.visibilityResult = .success(FakeUserPlaylistRepository.playlist(visibility: "private"))
        #expect(await viewModel.toggleVisibility() == "Playlist is now private")
        #expect(viewModel.visibilityTitle == "Make Public")
    }

    @Test func visibilityRejectionShowsServerMessageAndFailureIsSilent() async {
        let repository = FakeUserPlaylistRepository()
        repository.visibilityResult = .failure(UserPlaylistRepositoryError.rejected(message: "Nope"))
        let viewModel = makeViewModel(repository: repository)
        #expect(await viewModel.toggleVisibility() == "Nope")

        repository.visibilityResult = .failure(FakeUserPlaylistRepository.Failure())
        #expect(await viewModel.toggleVisibility() == nil)
    }

    @Test func followFlipsAndReportsServerMessage() async {
        let repository = FakeUserPlaylistRepository()
        repository.followResult = .success("Added to library")
        let viewModel = makeViewModel(repository: repository)
        #expect(!viewModel.isFollowing)
        #expect(await viewModel.toggleFollow() == .followed(message: "Added to library"))
        #expect(viewModel.isFollowing)

        repository.followResult = .success("Removed")
        #expect(await viewModel.toggleFollow() == .unfollowed(message: "Removed"))
        #expect(!viewModel.isFollowing)
        #expect(repository.followCalls == ["p1", "p1"])
    }

    @Test func followFailureRevertsAndUsesNetworkMessage() async {
        let repository = FakeUserPlaylistRepository()
        let viewModel = makeViewModel(repository: repository)
        let outcome = await viewModel.toggleFollow()
        #expect(outcome == .failed(message: UserPlaylistActionsViewModel.networkErrorMessage))
        #expect(!viewModel.isFollowing)
    }

    @Test func followStateComesFromSavedKeys() async {
        let library = FakeLibraryRepository()
        library.savedKeys = [UserPlaylistActionsViewModel.followKey(for: "p1")]
        let viewModel = makeViewModel(repository: FakeUserPlaylistRepository(), library: library)
        await viewModel.loadFollowState()
        #expect(viewModel.isFollowing)
    }

    @Test func shareURLIsMinted() async {
        let viewModel = makeViewModel(repository: FakeUserPlaylistRepository())
        #expect(await viewModel.makeShareURL() == URL(string: "https://example.com/p1"))
    }
}
