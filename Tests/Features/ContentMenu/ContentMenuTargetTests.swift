import Testing
@testable import Hallelujah

struct ContentMenuTargetTests {
    @Test func onlyCompanyPlaylistsAreShareable() {
        #expect(ContentMenuTarget.playlist(.fixture(id: "p", owner: .company)).shareTarget == .companyPlaylist(id: "p"))
        #expect(ContentMenuTarget.playlist(.fixture(owner: .creator(id: "c", name: nil))).shareTarget == nil)
    }

    @Test func playlistsOfEitherOwnerCanBeSavedToTheLibrary() {
        let company = ContentMenuTarget.playlist(.fixture(id: "p", owner: .company))
        #expect(company.libraryItem?.type == .companyPlaylist)
        #expect(company.libraryItem?.id == "p")
        #expect(ContentMenuTarget.playlist(.fixture(owner: .creator(id: nil, name: nil))).libraryItem?.type == .creatorPlaylist)
    }

    @Test func queueSourceTypeFollowsOwnerAndKind() {
        #expect(ContentMenuTarget.playlist(.fixture(type: "music", owner: .company)).queueSource.playerType == .companyPlaylist)
        #expect(ContentMenuTarget.playlist(.fixture(type: "music", owner: .creator(id: nil, name: nil))).queueSource.playerType == .album)
        #expect(ContentMenuTarget.playlist(.fixture(type: "episode", owner: .creator(id: nil, name: nil))).queueSource.playerType == .season)
    }

    @Test func titleComesFromThePlaylist() {
        #expect(ContentMenuTarget.playlist(.fixture(title: "Worship")).title == "Worship")
    }
}
