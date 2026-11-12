import CoreMedia
import Foundation
import VideoToolbox

/// What this device can decode, so the picker never offers the original video when it cannot be played.
///
/// The rules, in order:
/// - H.264 up to 1080p on the short side always plays.
/// - Larger H.264 and HEVC play only with hardware decode (4K is not worth software decoding).
/// - VP9 and AV1 play only with hardware decode.
/// - Anything else (ProRes, ...) does not play, and neither does an unknown codec.
///
/// The hardware question is injected, so the rules are testable without a device; `live` asks
/// VideoToolbox.
struct VideoDecodeCapability: Sendable {
    /// The largest short side H.264 is trusted to play on every supported device.
    static let alwaysDecodableShortSide = 1080

    /// Whether the device has a hardware decoder for a normalised codec name (`h264`, `hevc`, `vp9`,
    /// `av1`).
    private let supportsHardwareDecode: @Sendable (String) -> Bool

    init(supportsHardwareDecode: @escaping @Sendable (String) -> Bool) {
        self.supportsHardwareDecode = supportsHardwareDecode
    }

    /// Asks VideoToolbox about the real device.
    static let live = VideoDecodeCapability { codec in
        guard let type = Self.coreMediaType(forCodec: codec) else { return false }
        return VTIsHardwareDecodeSupported(type)
    }

    /// `false` when the codec is missing or not one we play. A source of unknown size is judged as
    /// large, so only a hardware decoder vouches for it.
    func canDecode(_ source: VideoSourceInfo?) -> Bool {
        guard let codec = Self.normalizedCodec(source?.codec) else { return false }
        switch codec {
        case "h264":
            if let shortSide = source?.shortSide, shortSide <= Self.alwaysDecodableShortSide { return true }
            return supportsHardwareDecode(codec)
        case "hevc", "vp9", "av1":
            return supportsHardwareDecode(codec)
        default:
            return false
        }
    }

    /// ffprobe's `codec_name`, folded to the four names above (`h265` is HEVC under another name,
    /// `avc` and `avc1` are H.264). `nil` for blank or unrecognised input.
    static func normalizedCodec(_ raw: String?) -> String? {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !name.isEmpty else {
            return nil
        }
        switch name {
        case "h264", "avc", "avc1": return "h264"
        case "hevc", "h265", "hvc1", "hev1": return "hevc"
        case "vp9": return "vp9"
        case "av1": return "av1"
        default: return nil
        }
    }

    private static func coreMediaType(forCodec codec: String) -> CMVideoCodecType? {
        switch codec {
        case "h264": kCMVideoCodecType_H264
        case "hevc": kCMVideoCodecType_HEVC
        // Spelled as four-character codes so the build does not depend on which SDK declares the
        // `kCMVideoCodecType_VP9` / `_AV1` constants: 'vp09' and 'av01'.
        case "vp9": 0x7670_3039
        case "av1": 0x6176_3031
        default: nil
        }
    }
}
