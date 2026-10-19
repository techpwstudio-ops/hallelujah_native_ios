import Testing
@testable import Hallelujah

struct CountryServiceTests {
    @Test func indiaOffsetResolvesToIndiaUnlessLocaleIsSriLanka() {
        #expect(CountryService.countryFromDevice(offsetMinutes: 330, localeRegion: nil) == "IN")
        #expect(CountryService.countryFromDevice(offsetMinutes: 330, localeRegion: "US") == "IN")
        #expect(CountryService.countryFromDevice(offsetMinutes: 330, localeRegion: "LK") == "LK")
    }

    @Test func otherOffsetsUseTwoLetterLocaleRegion() {
        #expect(CountryService.countryFromDevice(offsetMinutes: 0, localeRegion: "GB") == "GB")
        #expect(CountryService.countryFromDevice(offsetMinutes: 0, localeRegion: "GBR") == nil)
        #expect(CountryService.countryFromDevice(offsetMinutes: 0, localeRegion: nil) == nil)
    }
}
