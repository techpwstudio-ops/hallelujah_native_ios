import Foundation
import Testing
@testable import GHallelujah

struct DateFlexibleISO8601Tests {
    @Test func parsesPlainInternetDateTime() {
        let date = Date.parseFlexibleISO8601("2026-03-01T10:15:30Z")
        #expect(date == Date(timeIntervalSince1970: 1_772_360_130))
    }

    @Test func parsesFractionalSeconds() {
        let date = Date.parseFlexibleISO8601("2026-03-01T10:15:30.500Z")
        #expect(date == Date(timeIntervalSince1970: 1_772_360_130.5))
    }

    @Test func nilAndGarbageYieldNil() {
        #expect(Date.parseFlexibleISO8601(nil) == nil)
        #expect(Date.parseFlexibleISO8601("yesterday") == nil)
        #expect(Date.parseFlexibleISO8601("") == nil)
    }
}
