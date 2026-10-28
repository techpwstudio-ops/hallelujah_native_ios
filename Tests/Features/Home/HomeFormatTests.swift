import Testing
@testable import Hallelujah

/// `Formater.formatNumber` + the `mediaSongCount` / `mediaPodcastCount` /
/// `creatorFollowerCount` plurals (`lib/utils/formater.dart`, `app_en.arb`).
struct HomeFormatTests {
    @Test func oneIsSingularAndNeverAbbreviated() {
        #expect(HomeFormat.songCountText(1) == "1 Song")
        #expect(HomeFormat.podcastCountText(1) == "1 Podcast")
        #expect(HomeFormat.followerCountText(1) == "1 Follower")
    }

    @Test func zeroAndMissingCountsArePlural() {
        #expect(HomeFormat.songCountText(0) == "0 Songs")
        #expect(HomeFormat.songCountText(nil) == "0 Songs")
        #expect(HomeFormat.followerCountText(nil) == "0 Followers")
    }

    @Test func mediaCountsAreAbbreviatedButFollowersAreNot() {
        #expect(HomeFormat.songCountText(1_500) == "1.5K Songs")
        #expect(HomeFormat.podcastCountText(2_000_000) == "2M Podcasts")
        #expect(HomeFormat.followerCountText(1_500) == "1500 Followers")
    }
}
