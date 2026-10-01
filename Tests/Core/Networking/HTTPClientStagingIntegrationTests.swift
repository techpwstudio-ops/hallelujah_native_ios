import Testing
@testable import GHallelujah

/// Hits the real Staging backend (qa.api.hallelujah.today) — not a mock.
/// This is T05's own Done criterion ("a real endpoint round-trips against
/// Staging"), kept in its own file since it's an integration test, not a
/// unit test: it needs network access and a live QA backend to pass.
struct HTTPClientStagingIntegrationTests {
    @Test func geoCountryRoundTripsAgainstStaging() async throws {
        let client = HTTPClient(configuration: .staging)

        let response = try await client.send(.geoCountry)

        #expect(response.statusCode == 200)
        #expect(!response.data.isEmpty)
    }
}
