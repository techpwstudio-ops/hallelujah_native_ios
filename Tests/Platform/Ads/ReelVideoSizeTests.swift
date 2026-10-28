import CoreGraphics
import Testing
@testable import Hallelujah

/// How big a reel ad's video is drawn: the screen's width and its own height,
/// centred; only when that height does not fit is it scaled down. The Swift twin
/// of `test/ads/reel_video_size_test.dart`.
struct ReelVideoSizeTests {
    private let portrait: CGFloat = 9 / 16

    @Test func aPortraitReelOnATallPhoneIsTheScreenWideAndItsOwnHeight() {
        let size = reelVideoSize(available: CGSize(width: 390, height: 844), aspectRatio: portrait)

        #expect(size.width == 390)
        #expect(abs(size.height - 390 / portrait) < 0.001)
        #expect(size.height < 844) // room is left over to centre it in
    }

    @Test func aSquareReelIsASquareTheScreenWide() {
        let size = reelVideoSize(available: CGSize(width: 390, height: 844), aspectRatio: 1)

        #expect(size == CGSize(width: 390, height: 390))
    }

    @Test func aLandscapeVideoIsTheScreenWideAndShorterThanItIsWide() {
        let size = reelVideoSize(available: CGSize(width: 390, height: 844), aspectRatio: 16 / 9)

        #expect(size.width == 390)
        #expect(abs(size.height - 390 * 9 / 16) < 0.001)
    }

    @Test func aShortScreenScalesTheReelDownInsteadOfOverflowing() {
        // 9:16 at 390 wide wants 693 tall; only 600 is there.
        let size = reelVideoSize(available: CGSize(width: 390, height: 600), aspectRatio: portrait)

        #expect(size.height == 600)
        #expect(abs(size.width - 600 * portrait) < 0.001)
        #expect(size.width < 390)
    }

    @Test func aLandscapePhoneShowsAPortraitReelByItsHeight() {
        let size = reelVideoSize(available: CGSize(width: 844, height: 390), aspectRatio: portrait)

        #expect(size.height == 390)
        #expect(abs(size.width - 390 * portrait) < 0.001)
    }

    @Test func aTabletDoesNotBlowAReelUpPastTheScreen() {
        let size = reelVideoSize(available: CGSize(width: 820, height: 1180), aspectRatio: portrait)

        // 820 wide would need 1458 tall, so the height governs.
        #expect(size.height == 1180)
        #expect(abs(size.width - 1180 * portrait) < 0.001)
        #expect(size.width <= 820)
    }

    @Test func theShapeIsNeverChangedWhateverTheScreen() {
        let screens = [
            CGSize(width: 390, height: 844),
            CGSize(width: 390, height: 600),
            CGSize(width: 844, height: 390),
            CGSize(width: 820, height: 1180),
            CGSize(width: 320, height: 480),
        ]
        for screen in screens {
            let size = reelVideoSize(available: screen, aspectRatio: portrait)
            #expect(abs(size.width / size.height - portrait) < 0.0001, "\(screen)")
            #expect(size.width <= screen.width + 0.001, "\(screen)")
            #expect(size.height <= screen.height + 0.001, "\(screen)")
        }
    }

    @Test func aVideoThatHasNotReportedItsShapeYetHasNoSize() {
        let screen = CGSize(width: 390, height: 844)
        #expect(reelVideoSize(available: screen, aspectRatio: 0) == .zero)
        #expect(reelVideoSize(available: screen, aspectRatio: -1) == .zero)
        #expect(reelVideoSize(available: screen, aspectRatio: .nan) == .zero)
        #expect(reelVideoSize(available: screen, aspectRatio: .infinity) == .zero)
    }

    @Test func anAreaWithNoRoomHasNoSize() {
        #expect(reelVideoSize(available: .zero, aspectRatio: portrait) == .zero)
        #expect(reelVideoSize(available: CGSize(width: 390, height: 0), aspectRatio: portrait) == .zero)
        #expect(reelVideoSize(available: CGSize(width: CGFloat.infinity, height: 844), aspectRatio: portrait) == .zero)
        #expect(reelVideoSize(available: CGSize(width: 390, height: CGFloat.infinity), aspectRatio: portrait) == .zero)
    }
}
