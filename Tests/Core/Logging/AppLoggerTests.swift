import Testing
@testable import GHallelujah

struct AppLoggerTests {
    @Test func gatesMessagesBelowTheConfiguredMinimumLevel() {
        let logger = AppLogger(category: .app, minimumLevel: .warning)

        #expect(logger.isEnabled(for: .debug) == false)
        #expect(logger.isEnabled(for: .info) == false)
        #expect(logger.isEnabled(for: .warning) == true)
        #expect(logger.isEnabled(for: .error) == true)
    }
}
