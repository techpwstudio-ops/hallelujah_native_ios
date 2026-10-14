import Testing
@testable import GHallelujah

struct SiriPlayServiceTests {
    private func results(top: SearchTopResultItem? = nil, music: [Song] = [], episodes: [Song] = []) -> SearchResults {
        SearchResults(
            topResult: top, music: .page(music), episodes: .page(episodes),
            creators: .empty, playlists: .empty
        )
    }

    @Test func aSongTopResultWins() {
        let best = SiriPlayService.bestMatch(in: results(
            top: .song(.fixture(id: "top")), music: [.fixture(id: "first")]
        ))
        #expect(best?.id == "top")
    }

    @Test func otherTopResultKindsFallBackToTheFirstMusicHit() {
        let creator = SearchCreatorResult(id: "c", name: "N", image: nil, imageVariants: nil, followersCount: nil)
        let best = SiriPlayService.bestMatch(in: results(top: .creator(creator), music: [.fixture(id: "m1")]))
        #expect(best?.id == "m1")
    }

    @Test func episodesAreTheLastResort() {
        let best = SiriPlayService.bestMatch(in: results(episodes: [.fixture(id: "e1", type: "episode")]))
        #expect(best?.id == "e1")
    }

    @Test func noResultsMeansNothingToPlay() {
        #expect(SiriPlayService.bestMatch(in: results()) == nil)
    }

    @Test func activityTypeMatchesTheInfoPlistEntry() {
        #expect(SiriPlayService.activityType == "INPlayMediaIntent")
    }
}
