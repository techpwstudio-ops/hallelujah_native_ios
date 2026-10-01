import Foundation

/// Ports `AudioQuality` (`OurSession.selectedAudioQuality`, referenced from
/// `S3Service.effectiveAudioQuality`) — the user-facing playback quality
/// tiers, ordered lowest to highest so `Comparable` gives the "stricter cap
/// wins" comparison `selectBestVariant` (`s3_service.dart:148-176`) needs.
enum AudioQuality: String, Sendable, CaseIterable, Comparable, Codable {
    case low, standard, high

    private var rank: Int {
        switch self {
        case .low: 0
        case .standard: 1
        case .high: 2
        }
    }

    static func < (lhs: AudioQuality, rhs: AudioQuality) -> Bool {
        lhs.rank < rhs.rank
    }
}
