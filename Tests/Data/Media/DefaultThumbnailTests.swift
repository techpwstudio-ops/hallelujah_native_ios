import Foundation
import Testing
@testable import GHallelujah

struct DefaultThumbnailTests {
    private func symbol(_ name: String?) -> String? {
        DefaultThumbnail.path(for: name)?
            .replacingOccurrences(of: "hallelujah/system/public/avatars/", with: "")
            .replacingOccurrences(of: ".webp", with: "")
    }

    @Test func usesTheFirstLetterAnywhereInTheName() {
        #expect(symbol("Amazing Grace") == "a")
        #expect(symbol("🎵 Worship Night") == "w")
        #expect(symbol("1. Holy") == "h")
    }

    @Test func foldsLatinDiacritics() {
        #expect(symbol("Ávila") == "a")
        #expect(symbol("Çelik") == "c")
    }

    @Test func fallsBackToDigitThenDefault() {
        #expect(symbol("123") == "1")
        #expect(symbol("🎵🎵") == "default")
        #expect(symbol("") == "default")
    }

    @Test func nilNameHasNoTile() {
        #expect(DefaultThumbnail.path(for: nil) == nil)
    }

    @Test func pathShape() {
        #expect(DefaultThumbnail.path(for: "Zion") == "hallelujah/system/public/avatars/z.webp")
    }
}
