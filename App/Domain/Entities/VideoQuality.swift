import Foundation

/// The listener's choice of picture quality for an episode's silent video. Counterpart of
/// `AudioQuality`, with two differences: `auto` lets the app decide from the connection and battery,
/// and `original` is the creator's own upload rather than an encoded rung.
///
/// The raw values are the stored choice and, for the three rungs, the file names the backend writes
/// beside the video (`480p.mp4`, ...). Declared lowest to highest; `Comparable` ranks the rungs and
/// `original` above them. `auto` is a preference, not a quality, and has no place in that order.
enum VideoQuality: String, Sendable, CaseIterable, Comparable, Codable {
    case auto
    case p480 = "480p"
    case p720 = "720p"
    case p1080 = "1080p"
    case original

    /// The qualities a file can actually have, lowest to highest.
    static let concrete: [VideoQuality] = [.p480, .p720, .p1080, .original]

    /// The encoded rungs, lowest to highest: `concrete` without `original`.
    static let rungs: [VideoQuality] = [.p480, .p720, .p1080]

    var isRung: Bool { Self.rungs.contains(self) }

    private var rank: Int {
        switch self {
        case .auto: 0
        case .p480: 1
        case .p720: 2
        case .p1080: 3
        case .original: 4
        }
    }

    static func < (lhs: VideoQuality, rhs: VideoQuality) -> Bool {
        lhs.rank < rhs.rank
    }
}
