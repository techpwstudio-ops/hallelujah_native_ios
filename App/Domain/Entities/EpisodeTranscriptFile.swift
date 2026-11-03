import Foundation

/// The transcript file behind `episodeTranscript.url` (contract §3), flattened
/// for lookup: word `i` spans `startsMs[i]`...`endsMs[i]` and reads `words[i]`.
/// Words are used exactly as the file gives them, so a script is never split.
struct EpisodeTranscriptFile: Sendable, Equatable {
    /// A run of consecutive words spoken by one speaker.
    struct Segment: Sendable, Equatable {
        /// `nil` when the source has no speaker labels.
        let speaker: String?
        let wordRange: Range<Int>
    }

    let version: Int
    let language: String?
    let startsMs: [Int]
    let endsMs: [Int]
    let words: [String]
    let segments: [Segment]
}
