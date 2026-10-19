import Testing
@testable import Hallelujah

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

    @Test func singleSongEndpoints() {
        #expect(Endpoint.songDetail(id: "s1").path == "/song/s1")
        #expect(Endpoint.songDetail(id: "s1").method == .get)
        #expect(Endpoint.reportSong(id: "s1").path == "/song/s1/report")
        #expect(Endpoint.reportSong(id: "s1").method == .post)
    }

    @Test func helpersSetVerbAndBase() {
        #expect(Endpoint.get("/x").method == .get)
        #expect(Endpoint.post("/x").method == .post)
        #expect(Endpoint.patch("/x").method == .patch)
        #expect(Endpoint.delete("/x").method == .delete)
        #expect(Endpoint.get("/x").base == .api)
        #expect(Endpoint.get("/x", base: .proxy).base == .proxy)
    }

    @Test func uploadCreatorAndPremiumEndpoints() {
        #expect(Endpoint.presignedUpload.path == "/upload/generate/presigned")
        #expect(Endpoint.presignedUpload.method == .post)
        #expect(Endpoint.allCreators(page: 4).path == "/creators?page=4")
        #expect(Endpoint.cancelSubscription.path == "/premium/subscription/cancel")
        #expect(Endpoint.cancelSubscription.method == .get)
    }

    @Test func userPlaylistFollowAndVisibilityEndpoints() {
        #expect(Endpoint.toggleFollowUserPlaylist(id: "p1").path == "/library/user-playlist/p1/follow")
        #expect(Endpoint.toggleFollowUserPlaylist(id: "p1").method == .get)
        #expect(Endpoint.toggleUserPlaylistVisibility(id: "p1").path == "/library/user-playlist/p1/visibility")
        #expect(Endpoint.toggleUserPlaylistVisibility(id: "p1").method == .get)
        #expect(Endpoint.userPlaylistShare(id: "p1").path == "/library/user-playlist/p1/share")
    }
}
