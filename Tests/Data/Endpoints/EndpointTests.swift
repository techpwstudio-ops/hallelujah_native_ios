import Testing
@testable import GHallelujah

/// The API contract lives in `Endpoint` (never inline in a repository), so
/// these pin the exact path + verb each repository depends on.
struct EndpointTests {
    @Test func homeV2Endpoints() {
        let layout = Endpoint.homeLayout(type: .all, withSections: 6)
        #expect(layout.path == "/v2/home/layout/all?withSections=6")
        #expect(layout.method == .get)

        #expect(Endpoint.homeFeed(type: .music, offset: 12, limit: 6).path == "/v2/home/feed/music?offset=12&limit=6")
        #expect(Endpoint.homeSection(type: .episode, uiId: "recent-all", page: 2).path
            == "/v2/home/section/episode/recent-all?page=2")
    }

    @Test func libraryAndFavouriteEndpoints() {
        #expect(Endpoint.libraryCount(type: .all).path == "/library/content/count/all")
        #expect(Endpoint.libraryItems(type: .music, page: 3).path == "/library/items?page=3&type=music")
        #expect(Endpoint.favoriteSongs(type: .all, page: 1).path == "/song/favorite?type=all&page=1")
        #expect(Endpoint.favoriteCreators(type: .all, page: 1).path == "/creators/favorite?page=1&type=all")
    }

    @Test func toggleFavouriteCarriesTheTargetValue() {
        #expect(Endpoint.toggleSongFavorite(songId: "abc", isFavorited: true).path
            == "/song/toggle/favorite/abc?value=true")
        #expect(Endpoint.toggleSongFavorite(songId: "abc", isFavorited: false).path
            == "/song/toggle/favorite/abc?value=false")
    }

    @Test func genreAndAuthEndpoints() {
        #expect(Endpoint.genreSongs(id: "g1", page: 2).path == "/genre/songs/g1?page=2")
        #expect(Endpoint.authOTPSend.method == .post)
        #expect(Endpoint.refreshToken.path == "/auth/token/refresh")
        #expect(Endpoint.logout.method == .get)
    }

    @Test func helpersSetVerbAndBase() {
        #expect(Endpoint.get("/x").method == .get)
        #expect(Endpoint.post("/x").method == .post)
        #expect(Endpoint.patch("/x").method == .patch)
        #expect(Endpoint.delete("/x").method == .delete)
        #expect(Endpoint.get("/x").base == .api)
        #expect(Endpoint.get("/x", base: .proxy).base == .proxy)
    }
}
