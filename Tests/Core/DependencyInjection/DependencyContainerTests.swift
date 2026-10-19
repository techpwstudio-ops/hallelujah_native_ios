import Foundation
import Testing
@testable import Hallelujah

struct DependencyContainerTests {
    @Test func resolveReturnsTheRegisteredInstance() {
        let container = DependencyContainer()
        container.register((any ClockProviding).self) { FixedClock(date: Date(timeIntervalSince1970: 42)) }

        let clock: any ClockProviding = container.resolve()

        #expect(clock.now() == Date(timeIntervalSince1970: 42))
    }
}
