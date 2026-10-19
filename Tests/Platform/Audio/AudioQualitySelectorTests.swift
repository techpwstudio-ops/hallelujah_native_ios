import Testing
@testable import Hallelujah

struct AudioQualitySelectorTests {
    private func selector(
        stored: AudioQuality? = nil,
        lowBattery: Bool = false,
        connection: ConnectionType? = .wifi
    ) -> AudioQualitySelector {
        let store = InMemoryKeyValueStore()
        let selector = AudioQualitySelector(
            keyValueStore: store,
            batteryMonitor: FakeBatteryMonitor(isLowBattery: lowBattery),
            connectivityType: FakeConnectivity(currentConnectionType: connection)
        )
        if let stored { selector.setUserSelectedQuality(stored) }
        return selector
    }

    @Test func defaultsToStandardWhenNothingIsStored() async {
        #expect(await selector().userSelectedQuality == .standard)
    }

    @Test func rememberedChoiceRoundTrips() async {
        #expect(await selector(stored: .high).userSelectedQuality == .high)
        #expect(await selector(stored: .low).userSelectedQuality == .low)
    }

    @Test func wifiHonoursTheUsersChoice() async {
        #expect(await selector(stored: .high, connection: .wifi).targetQuality() == .high)
        #expect(await selector(stored: .low, connection: .wifi).targetQuality() == .low)
    }

    @Test func cellularCapsAtStandard() async {
        #expect(await selector(stored: .high, connection: .cellular).targetQuality() == .standard)
        #expect(await selector(stored: .low, connection: .cellular).targetQuality() == .low)
    }

    @Test func noConnectionDropsToLow() async {
        #expect(await selector(stored: .high, connection: ConnectionType.none).targetQuality() == .low)
    }

    @Test func lowBatteryForcesLowBeforeTheNetworkCap() async {
        #expect(await selector(stored: .high, lowBattery: true, connection: .wifi).targetQuality() == .low)
    }

    @Test func unknownConnectionLeavesTheChoiceUntouched() async {
        #expect(await selector(stored: .high, connection: nil).targetQuality() == .high)
    }

    @Test func qualityIsOrderedLowToHigh() {
        #expect(AudioQuality.low < .standard)
        #expect(AudioQuality.standard < .high)
        #expect(AudioQuality.allCases.sorted() == [.low, .standard, .high])
    }
}
