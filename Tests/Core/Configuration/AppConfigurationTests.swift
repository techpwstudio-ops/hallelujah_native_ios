import Foundation
import Testing
@testable import Hallelujah

/// These assertions must hold for every scheme (Development/Staging/Production),
/// since the same test target runs under all three. They check the parsed
/// config is internally consistent with the actual build it's running in,
/// rather than hardcoding one environment's expected values.
struct AppConfigurationTests {
    /// Every environment ships under the one bundle identifier:
    /// `APP_BUNDLE_ID_SUFFIX` is empty in all of `Config/Environments/*.xcconfig`,
    /// so there is no side-by-side `.dev` / `.staging` build.
    @Test func noEnvironmentAddsABundleIdentifierSuffix() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        #expect(!bundleID.hasSuffix(".dev"))
        #expect(!bundleID.hasSuffix(".staging"))
    }

    @Test func apiBaseURLIsWellFormed() {
        let apiBaseURL = AppConfiguration.current.apiBaseURL
        #expect(apiBaseURL.host != nil)
        #expect(apiBaseURL.path == "/api")
        #expect(apiBaseURL.scheme == "http" || apiBaseURL.scheme == "https")
    }

    @Test func proxyAndSocketURLsAreWellFormed() {
        let config = AppConfiguration.current
        #expect(config.proxyBaseURL.host != nil)
        #expect(config.proxyBaseURL.path == "/api")
        #expect(config.socketBaseURL.host != nil)
    }

    @Test func websiteAndCDNHostsAreConstantAcrossEnvironments() {
        let config = AppConfiguration.current
        #expect(config.websiteHost == "hallelujah.today")
        #expect(config.cdnHost == "d124ttxt2as03p.cloudfront.net")
    }

    @Test func developmentIsTheOnlyEnvironmentAllowingArbitraryLoads() {
        let config = AppConfiguration.current
        let atsException = (Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any])?["NSAllowsArbitraryLoads"] as? Bool ?? false
        #expect(atsException == (config.environment == .development))
    }
}
