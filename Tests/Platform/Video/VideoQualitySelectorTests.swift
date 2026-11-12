import Testing
@testable import Hallelujah

struct VideoQualitySelectorTests {
    private let wifi = VideoQualityConditions(connection: .wifi)
    private let cellular = VideoQualityConditions(connection: .cellular)

    private func renditions(_ variants: String?, original: Bool = true) -> VideoRenditions {
        VideoQualitySelector.renditions(videoVariants: variants, originalIsPlayable: original)
    }

    private func choose(
        _ preference: VideoQuality,
        _ variants: String?,
        original: Bool = true,
        _ conditions: VideoQualityConditions
    ) -> VideoQualityChoice {
        VideoQualitySelector.choose(
            preference: preference,
            renditions: renditions(variants, original: original),
            conditions: conditions
        )
    }

    private let all = "480p.mp4,720p.mp4,1080p.mp4"

    // MARK: Quality

    @Test func qualityIsOrderedLowToHigh() {
        #expect(VideoQuality.p480 < .p720)
        #expect(VideoQuality.p720 < .p1080)
        #expect(VideoQuality.p1080 < .original)
        #expect(VideoQuality.concrete == [.p480, .p720, .p1080, .original])
    }

    @Test func rawValuesAreTheStoredForm() {
        #expect(VideoQuality.allCases.map(\.rawValue) == ["auto", "480p", "720p", "1080p", "original"])
    }

    // MARK: Renditions

    @Test func rungsComeFromTheList() {
        let result = renditions("480p.mp4, 720p.mp4")
        #expect(result.qualities == [.p480, .p720, .original])
        #expect(result.variantFileNames[.p720] == "720p.mp4")
    }

    @Test func originalIsOfferedOnlyWhenPlayable() {
        #expect(renditions(all, original: false).qualities == [.p480, .p720, .p1080])
    }

    @Test func unknownAndUnsafeTokensAreIgnored() {
        let result = renditions("360p.mp4,../480p.mp4,480p.mp4/x,auto,original,,720p.mp4")
        #expect(result.qualities == [.p720, .original])
    }

    @Test func noListMeansNoVariants() {
        for value in [nil, "", "  "] {
            let result = renditions(value)
            #expect(!result.hasVariants)
            #expect(result.qualities == [.original])
        }
    }

    // MARK: Auto

    @Test func autoOnWifiTakesTheHighestRungNotTheOriginal() {
        #expect(choose(.auto, all, wifi) == VideoQualityChoice(quality: .p1080, variantFileName: "1080p.mp4"))
        #expect(choose(.auto, "480p.mp4,720p.mp4", wifi).quality == .p720)
        #expect(choose(.auto, "480p.mp4", wifi).quality == .p480)
    }

    @Test func autoOnEthernetOrAnUnknownConnectionActsLikeWifi() {
        #expect(choose(.auto, all, VideoQualityConditions(connection: .ethernet)).quality == .p1080)
        #expect(choose(.auto, all, VideoQualityConditions(connection: nil)).quality == .p1080)
    }

    @Test func autoOnCellularOrOfflineTakes480p() {
        #expect(choose(.auto, all, cellular) == VideoQualityChoice(quality: .p480, variantFileName: "480p.mp4"))
        #expect(choose(.auto, all, VideoQualityConditions(connection: ConnectionType.none)).quality == .p480)
        #expect(choose(.auto, all, VideoQualityConditions(connection: .other)).quality == .p480)
    }

    @Test func autoOnLowBatteryOrLowPowerModeTakes480pEvenOnWifi() {
        #expect(choose(.auto, all, VideoQualityConditions(connection: .wifi, isLowBattery: true)).quality == .p480)
        #expect(choose(.auto, all, VideoQualityConditions(connection: .wifi, isLowPowerMode: true)).quality == .p480)
    }

    // MARK: Explicit choices

    @Test func anExplicitChoiceIsHonouredEvenOnCellular() {
        #expect(choose(.p1080, all, cellular).quality == .p1080)
        #expect(choose(.p720, all, VideoQualityConditions(connection: .cellular, isLowBattery: true)).quality == .p720)
    }

    @Test func aMissingRungFallsToTheNextLowerOne() {
        #expect(choose(.p1080, "480p.mp4,720p.mp4", wifi).quality == .p720)
        #expect(choose(.p720, "480p.mp4", wifi).quality == .p480)
        #expect(choose(.p1080, "480p.mp4,1080p.mp4", wifi).quality == .p1080)
    }

    @Test func aChoiceBelowEveryRungGetsTheLowest() {
        #expect(choose(.p480, "720p.mp4,1080p.mp4", wifi).quality == .p720)
    }

    @Test func originalPlaysTheVideoFileWhenPlayable() {
        #expect(choose(.original, all, wifi) == .original)
        #expect(choose(.original, all, cellular) == .original)
    }

    @Test func anUnplayableOriginalFallsToTheBestRung() {
        #expect(choose(.original, all, original: false, wifi).quality == .p1080)
        #expect(choose(.original, "480p.mp4,720p.mp4", original: false, wifi).quality == .p720)
    }

    // MARK: No variants

    @Test func noVariantsPlaysTheVideoFileWhateverTheChoice() {
        for preference in VideoQuality.allCases {
            #expect(choose(preference, nil, wifi) == .original)
            #expect(choose(preference, nil, original: false, cellular) == .original)
        }
    }

    // MARK: Conditions and persistence

    private func selector(
        stored: VideoQuality? = nil,
        lowBattery: Bool = false,
        lowPower: Bool = false,
        connection: ConnectionType? = .wifi,
        hardware: Set<String> = []
    ) -> VideoQualitySelector {
        let selector = VideoQualitySelector(
            keyValueStore: InMemoryKeyValueStore(),
            batteryMonitor: FakeBatteryMonitor(isLowBattery: lowBattery),
            connectivityType: FakeConnectivity(currentConnectionType: connection),
            lowPowerMode: FakeLowPowerMode(isLowPowerModeEnabled: lowPower),
            capability: VideoDecodeCapability { hardware.contains($0) }
        )
        if let stored { selector.setUserSelectedQuality(stored) }
        return selector
    }

    @Test func defaultsToAuto() {
        #expect(selector().userSelectedQuality == .auto)
    }

    @Test func theChoiceRoundTrips() {
        for quality in VideoQuality.allCases {
            #expect(selector(stored: quality).userSelectedQuality == quality)
        }
    }

    @Test func anUnreadableStoredValueMeansAuto() {
        let store = InMemoryKeyValueStore()
        store.setString("4k", forKey: "video.selectedQuality")
        let selector = VideoQualitySelector(
            keyValueStore: store,
            batteryMonitor: FakeBatteryMonitor(isLowBattery: false),
            connectivityType: FakeConnectivity(currentConnectionType: .wifi),
            lowPowerMode: FakeLowPowerMode(isLowPowerModeEnabled: false),
            capability: VideoDecodeCapability { _ in false }
        )
        #expect(selector.userSelectedQuality == .auto)
    }

    @Test func conditionsCarryTheLiveSignals() async {
        let conditions = await selector(lowBattery: true, lowPower: true, connection: .cellular).currentConditions()
        #expect(conditions == VideoQualityConditions(connection: .cellular, isLowBattery: true, isLowPowerMode: true))
    }

    @Test func renditionsForASongUseTheDeviceCapability() {
        let source = VideoSourceInfo(codec: "hevc", width: 3840, height: 2160, fps: 30, bitrate: nil)
        let song = Song.fixture(videoFile: "a/original.mp4", videoVariants: "480p.mp4", videoSource: source)
        #expect(selector().renditions(for: song).qualities == [.p480])
        #expect(selector(hardware: ["hevc"]).renditions(for: song).qualities == [.p480, .original])
    }

    @Test func aSongWithVariantsButNoSourceInfoDoesNotOfferTheOriginal() {
        let song = Song.fixture(videoFile: "a/original.mp4", videoVariants: all)
        #expect(selector(hardware: ["h264", "hevc"]).renditions(for: song).qualities == [.p480, .p720, .p1080])
    }

    @Test func choiceForASongReadsTheStoredPreference() {
        let song = Song.fixture(videoFile: "a/original.mp4", videoVariants: all)
        #expect(selector(stored: .p720).choice(for: song, conditions: cellular).quality == .p720)
        #expect(selector().choice(for: song, conditions: cellular).quality == .p480)
        #expect(selector().choice(for: song, conditions: wifi).quality == .p1080)
    }
}
