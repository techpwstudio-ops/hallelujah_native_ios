import Foundation
import Testing
@testable import Hallelujah

struct ReaderVerseOpenerTests {
    @Test func parsesNumbersAndNumericStrings() {
        #expect(ReaderVerseOpener.int(5) == 5)
        #expect(ReaderVerseOpener.int("12") == 12)
        #expect(ReaderVerseOpener.int(NSNumber(value: 3)) == 3)
        #expect(ReaderVerseOpener.int("x") == nil)
        #expect(ReaderVerseOpener.int(nil) == nil)
    }
}
