import Testing
@testable import Hallelujah

struct VideoDecodeCapabilityTests {
    private func capability(hardware: Set<String> = []) -> VideoDecodeCapability {
        VideoDecodeCapability { hardware.contains($0) }
    }

    private func source(_ codec: String?, _ width: Int?, _ height: Int?) -> VideoSourceInfo {
        VideoSourceInfo(codec: codec, width: width, height: height, fps: nil, bitrate: nil)
    }

    @Test func h264UpToFullHDAlwaysPlays() {
        let none = capability()
        #expect(none.canDecode(source("h264", 1920, 1080)))
        #expect(none.canDecode(source("h264", 1280, 720)))
        #expect(none.canDecode(source("h264", 1080, 1920)))  // vertical: short side 1080
    }

    @Test func largerH264NeedsHardwareDecode() {
        #expect(!capability().canDecode(source("h264", 3840, 2160)))
        #expect(capability(hardware: ["h264"]).canDecode(source("h264", 3840, 2160)))
    }

    @Test func h264OfUnknownSizeNeedsHardwareDecode() {
        #expect(!capability().canDecode(source("h264", nil, nil)))
        #expect(capability(hardware: ["h264"]).canDecode(source("h264", nil, nil)))
    }

    @Test func hevcNeedsHardwareDecodeAtAnySize() {
        #expect(!capability().canDecode(source("hevc", 1920, 1080)))
        #expect(capability(hardware: ["hevc"]).canDecode(source("hevc", 1920, 1080)))
        #expect(capability(hardware: ["hevc"]).canDecode(source("hevc", 3840, 2160)))
    }

    @Test func vp9AndAV1PlayOnlyWithHardwareDecode() {
        for codec in ["vp9", "av1"] {
            #expect(!capability().canDecode(source(codec, 1280, 720)))
            #expect(capability(hardware: [codec]).canDecode(source(codec, 1280, 720)))
        }
    }

    @Test func otherCodecsNeverPlay() {
        let everything = capability(hardware: ["h264", "hevc", "vp9", "av1", "prores"])
        #expect(!everything.canDecode(source("prores", 1920, 1080)))
        #expect(!everything.canDecode(source("mpeg4", 640, 360)))
    }

    @Test func missingSourceOrCodecNeverPlays() {
        let everything = capability(hardware: ["h264", "hevc", "vp9", "av1"])
        #expect(!everything.canDecode(nil))
        #expect(!everything.canDecode(source(nil, 1280, 720)))
        #expect(!everything.canDecode(source("  ", 1280, 720)))
    }

    @Test func codecNamesAreNormalised() {
        #expect(VideoDecodeCapability.normalizedCodec("H264") == "h264")
        #expect(VideoDecodeCapability.normalizedCodec(" avc1 ") == "h264")
        #expect(VideoDecodeCapability.normalizedCodec("h265") == "hevc")
        #expect(VideoDecodeCapability.normalizedCodec("HEVC") == "hevc")
        #expect(VideoDecodeCapability.normalizedCodec("prores") == nil)
        #expect(VideoDecodeCapability.normalizedCodec(nil) == nil)
    }
}
