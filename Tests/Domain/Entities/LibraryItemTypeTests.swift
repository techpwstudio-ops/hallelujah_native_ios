import Testing
@testable import GHallelujah

struct LibraryItemTypeTests {
    @Test func apiNamesMatchTheBackendEnum() {
        #expect(LibraryItemType.creatorPlaylist.apiName == "creatorPlaylist")
        #expect(LibraryItemType.companyPlaylist.apiName == "companyPlaylist")
    }

    @Test func compositeKeysNeverCollideAcrossTypes() {
        #expect(LibraryItemType.creatorPlaylist.key(for: "7") == "creatorPlaylist:7")
        #expect(LibraryItemType.companyPlaylist.key(for: "7") == "companyPlaylist:7")
        #expect(LibraryItemType.creatorPlaylist.key(for: "7") != LibraryItemType.companyPlaylist.key(for: "7"))
    }

    @Test func playlistsSaveIntoTheBucketTheirOwnerImplies() {
        #expect(Playlist.fixture(owner: .company).libraryItemType == .companyPlaylist)
        #expect(Playlist.fixture(owner: .creator(id: "c", name: "N")).libraryItemType == .creatorPlaylist)
    }
}
