import Testing
@testable import Hallelujah

@MainActor
struct PlayerVideoModeStoreTests {
    @Test func startsOnTheCover() {
        #expect(!PlayerVideoModeStore().showsVideo)
    }

    @Test func showVideoAndShowCoverSetTheChoice() {
        let store = PlayerVideoModeStore()
        store.showVideo()
        #expect(store.showsVideo)
        store.showCover()
        #expect(!store.showsVideo)
    }

    @Test func toggleFlipsTheChoiceBothWays() {
        let store = PlayerVideoModeStore()
        store.toggle()
        #expect(store.showsVideo)
        store.toggle()
        #expect(!store.showsVideo)
    }

    @Test func askingForTheSameThingTwiceChangesNothing() {
        let store = PlayerVideoModeStore()
        store.showVideo()
        store.showVideo()
        #expect(store.showsVideo)
        store.showCover()
        store.showCover()
        #expect(!store.showsVideo)
    }

    @Test func eachStoreHasItsOwnChoice() {
        let a = PlayerVideoModeStore()
        let b = PlayerVideoModeStore()
        a.showVideo()
        #expect(!b.showsVideo)
    }
}
