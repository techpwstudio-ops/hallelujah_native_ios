import Foundation
import Testing
@testable import Hallelujah

@MainActor
struct UserPlaylistActionsViewModelTests {
    private func makeViewModel(
        repository: FakeUserPlaylistRepository,
        library: FakeLibraryRepository = FakeLibraryRepository(),
        overrides: UserPlaylistVisibilityOverrides? = nil
    ) -> UserPlaylistActionsViewModel {
        // Never `.shared`: tests must not see each other's toggles.
        UserPlaylistActionsViewModel(
            playlistID: "p1",
            repository: repository,
            libraryRepository: library,
            shareLink: { id in URL(string: "https://example.com/\(id)")! },
            overrides: overrides ?? UserPlaylistVisibilityOverrides()
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

    @Test func visibilityRejectionShowsServerMessageAndFailureShowsNetworkError() async {
        let repository = FakeUserPlaylistRepository()
        repository.visibilityResult = .failure(UserPlaylistRepositoryError.rejected(message: "Nope"))
        let viewModel = makeViewModel(repository: repository)
        #expect(await viewModel.toggleVisibility() == "Nope")

        repository.visibilityResult = .failure(FakeUserPlaylistRepository.Failure())
        #expect(await viewModel.toggleVisibility() == UserPlaylistActionsViewModel.networkErrorMessage)
    }

    @Test func confirmedVisibilityIsHeldOverStaleFetches() async {
        let repository = FakeUserPlaylistRepository()
        let overrides = UserPlaylistVisibilityOverrides()
        let viewModel = makeViewModel(repository: repository, overrides: overrides)
        viewModel.setVisibility("private")
        repository.visibilityResult = .success(FakeUserPlaylistRepository.playlist(visibility: "public"))
        _ = await viewModel.toggleVisibility()
        #expect(overrides.resolve("private", for: "p1") == "public")
    }

    /// A failed call may still have flipped it server-side (a timeout after
    /// the write), so the put-back value must not mask the next fetch.
    @Test func failedToggleRevertsWithoutHoldingTheOldValue() async {
        let repository = FakeUserPlaylistRepository()
        let overrides = UserPlaylistVisibilityOverrides()
        let viewModel = makeViewModel(repository: repository, overrides: overrides)
        viewModel.setVisibility("private")
        _ = await viewModel.toggleVisibility()
        #expect(viewModel.visibility == "private")
        #expect(overrides.resolve("public", for: "p1") == "public")
        #expect(!viewModel.isTogglingVisibility)
    }

    @Test func toggleWaitsForOneAlreadyInFlight() async {
        let repository = FakeUserPlaylistRepository()
        repository.visibilityResult = .success(FakeUserPlaylistRepository.playlist(visibility: "public"))
        let overrides = UserPlaylistVisibilityOverrides()
        let viewModel = makeViewModel(repository: repository, overrides: overrides)
        viewModel.setVisibility("private")
        #expect(overrides.beginToggle(for: "p1"))
        #expect(viewModel.isTogglingVisibility)
        #expect(await viewModel.toggleVisibility() == "")
        #expect(repository.visibilityCalls.isEmpty)
        #expect(viewModel.visibility == "private")

        overrides.endToggle(for: "p1")
        #expect(await viewModel.toggleVisibility() == "Playlist is now public")
        #expect(repository.visibilityCalls == ["p1"])
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
