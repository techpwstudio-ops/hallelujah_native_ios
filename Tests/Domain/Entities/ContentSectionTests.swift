import Testing
@testable import GHallelujah

struct ContentSectionTests {
    @Test func hasMoreAndPageComeFromTheUnderlyingPage() {
        let content = SectionContent.songs(.page([Song.fixture()], hasMore: true, page: 2))
        #expect(content.hasMore)
        #expect(content.currentPage == 2)
        #expect(!SectionContent.unsupported(viewType: "verseOfDay").hasMore)
        #expect(SectionContent.unsupported(viewType: "verseOfDay").currentPage == 1)
    }

    @Test func appendingConcatenatesItemsAndTakesTheNewerPageMeta() {
        let first = SectionContent.songs(.page([Song.fixture(id: "a")], hasMore: true, page: 1))
        let second = SectionContent.songs(.page([Song.fixture(id: "b")], hasMore: false, page: 2))

        guard case .songs(let merged) = first.appending(second) else {
            Issue.record("appending changed the content case")
            return
        }
        #expect(merged.items.map(\.id) == ["a", "b"])
        #expect(merged.page == 2)
        #expect(!merged.hasMore)
    }

    @Test func appendingAMismatchedCaseFallsBackToTheNewContent() {
        let songs = SectionContent.songs(.page([Song.fixture()]))
        let playlists = SectionContent.playlists(.page([Playlist.fixture()]))
        #expect(songs.appending(playlists) == playlists)
    }

    @Test func recentItemFlagsFollowItemType() {
        func item(_ type: String, contentType: String? = nil) -> RecentContentItem {
            RecentContentItem(
                id: "1", itemType: type, entityId: nil, title: nil, subtitle: nil, image: nil,
                imageVariants: nil, playedAt: nil, songId: nil, contentType: contentType
            )
        }
        #expect(item("song").isSong)
        #expect(item("album").isCreatorPlaylist)
        #expect(item("season").isCreatorPlaylist)
        #expect(item("companyPlaylist").isCompanyPlaylist)
        #expect(item("season").isEpisode)
        #expect(item("song", contentType: "episode").isEpisode)
        #expect(!item("song", contentType: "music").isEpisode)
    }

    @Test func playlistKindFollowsType() {
        #expect(Playlist.fixture(type: "episode").isSeason)
        #expect(Playlist.fixture(type: "music").isAlbum)
    }
}
