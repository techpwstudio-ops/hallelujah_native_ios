import Foundation

/// The transcript file (`episodeTranscript.url`, contract §3). Only `format` 1
/// is understood. A higher or missing `format` gives no transcript, not an error.
struct TranscriptFileDTO: Decodable, Sendable {
    let format: Int?
    let version: Int?
    let language: String?
    let segments: LossyArray<TranscriptSegmentDTO>?
}

struct TranscriptSegmentDTO: Decodable, Sendable {
    let speaker: String?
    let startMs: Int
    let endMs: Int
    let words: LossyArray<TranscriptWordDTO>?
}

/// A word is `[startMs, endMs, text]`, so it decodes from an unkeyed container.
/// A word that does not fit that shape fails here, and `LossyArray` drops it.
struct TranscriptWordDTO: Decodable, Sendable {
    let startMs: Int
    let endMs: Int
    let text: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        startMs = try container.decode(Int.self)
        endMs = try container.decode(Int.self)
        text = try container.decode(String.self)
    }
}

extension TranscriptFileDTO {
    /// Flattens the file. Returns `nil` for an unsupported `format`. Empty
    /// segments are dropped, so every kept segment has at least one word.
    func toDomain() -> EpisodeTranscriptFile? {
        guard format == 1 else { return nil }
        var startsMs: [Int] = []
        var endsMs: [Int] = []
        var words: [String] = []
        var kept: [EpisodeTranscriptFile.Segment] = []
        for segment in segments?.items ?? [] {
            let first = words.count
            for word in segment.words?.items ?? [] where word.endMs >= word.startMs {
                startsMs.append(word.startMs)
                endsMs.append(word.endMs)
                words.append(word.text)
            }
            guard words.count > first else { continue }
            let speaker = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines)
            kept.append(EpisodeTranscriptFile.Segment(
                speaker: speaker?.isEmpty == false ? speaker : nil,
                wordRange: first..<words.count
            ))
        }
        return EpisodeTranscriptFile(
            version: version ?? 0,
            language: language,
            startsMs: startsMs,
            endsMs: endsMs,
            words: words,
            segments: kept
        )
    }
}
