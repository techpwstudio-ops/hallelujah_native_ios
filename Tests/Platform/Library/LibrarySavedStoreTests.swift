import Testing
@testable import GHallelujah

@MainActor
struct LibrarySavedStoreTests {
    private let repository = FakeLibraryRepository()

    private func makeStore() -> LibrarySavedStore {
        LibrarySavedStore(repository: repository)
    }

    @Test func refreshLoadsTheSavedSetOnce() async {
        repository.savedKeys = ["companyPlaylist:p1"]
        let store = makeStore()

        await store.refreshIfNeeded()
        #expect(store.isLoaded)
        #expect(store.isSaved(.companyPlaylist, id: "p1"))
        #expect(!store.isSaved(.creatorPlaylist, id: "p1"))

        repository.savedKeys = []
        await store.refreshIfNeeded() // already loaded: no refetch
        #expect(store.isSaved(.companyPlaylist, id: "p1"))
    }

    @Test func aFailedRefreshStaysUnloadedAndEmpty() async {
        repository.fetchSavedKeysError = FakeLibraryRepository.Failure()
        let store = makeStore()
        await store.refresh()
        #expect(!store.isLoaded)
        #expect(store.savedKeys.isEmpty)
    }

    @Test func togglingSavesAnUnsavedItem() async {
        let store = makeStore()
        let result = await store.toggle(.creatorPlaylist, id: "a1")
        #expect(result == .saved)
        #expect(store.isSaved(.creatorPlaylist, id: "a1"))
    }

    @Test func togglingRemovesASavedItem() async {
        repository.savedKeys = ["creatorPlaylist:a1"]
        let store = makeStore()
        await store.refresh()

        let result = await store.toggle(.creatorPlaylist, id: "a1")
        #expect(result == .removed)
        #expect(!store.isSaved(.creatorPlaylist, id: "a1"))
    }

    @Test func aFailedToggleRevertsTheOptimisticFlip() async {
        repository.toggleError = FakeLibraryRepository.Failure()
        let store = makeStore()
        let result = await store.toggle(.companyPlaylist, id: "p1")
        #expect(result == .failed)
        #expect(!store.isSaved(.companyPlaylist, id: "p1"))
    }

    @Test func theServersVerdictWinsOverTheOptimisticGuess() async {
        // Guess says "saved"; the server says it was already in the library
        // and is now removed (toggled from another device in between).
        repository.toggleVerdict = false
        let store = makeStore()
        let result = await store.toggle(.companyPlaylist, id: "p1")
        #expect(result == .removed)
        #expect(!store.isSaved(.companyPlaylist, id: "p1"))
    }

    @Test func clearForgetsEverything() async {
        repository.savedKeys = ["companyPlaylist:p1"]
        let store = makeStore()
        await store.refresh()
        store.clear()
        #expect(!store.isLoaded)
        #expect(store.savedKeys.isEmpty)
    }
}
