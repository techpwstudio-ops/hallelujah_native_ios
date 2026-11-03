import Foundation

/// Time lookups over one episode's chapters and transcript. A pure value type
/// with no UI imports. All times are whole milliseconds.
///
/// Chapters are read at the playhead as it is. Words are read at
/// `positionMs - offsetMs`, the contract's one `offsetMs` rule. Between two
/// words the active word is the last one that started.
struct TimelineIndex: Sendable, Equatable {
    /// A gap longer than this pauses the now-speaking bars (Phase 2 rule).
    static let speechGapMs = 700

    private let chapterStartsMs: [Int]
    private let transcript: EpisodeTranscriptFile?
    private let segmentStartWords: [Int]
    private let offsetMs: Int

    init(chapters: [EpisodeChapter], transcript: EpisodeTranscriptFile? = nil, offsetMs: Int = 0) {
        chapterStartsMs = chapters.map(\.startMs)
        self.transcript = transcript
        segmentStartWords = transcript?.segments.map(\.wordRange.lowerBound) ?? []
        self.offsetMs = offsetMs
    }

    /// The chapter playing at `positionMs`: the last one that has started. `nil`
    /// before the first chapter, or with no chapters.
    func activeChapterIndex(positionMs: Int) -> Int? {
        Self.lastIndex(in: chapterStartsMs, atMost: positionMs)
    }

    /// The word being spoken at `positionMs`. `nil` before the first word.
    /// After the last word it stays on the last one, as the gap rule says.
    func activeWordIndex(positionMs: Int) -> Int? {
        guard let transcript else { return nil }
        return Self.lastIndex(in: transcript.startsMs, atMost: positionMs - offsetMs)
    }

    /// The segment (paragraph) that contains `wordIndex`.
    func segmentIndex(forWord wordIndex: Int) -> Int? {
        Self.lastIndex(in: segmentStartWords, atMost: wordIndex)
    }

    /// The speaker label of the segment that contains `wordIndex`. `nil` when
    /// the file has no label there.
    func speakerLabel(forWord wordIndex: Int) -> String? {
        guard let transcript, let segment = segmentIndex(forWord: wordIndex) else { return nil }
        return transcript.segments[segment].speaker
    }

    /// False in silence. The bars pause when the gap after the active word is
    /// longer than `speechGapMs`, and after the last word.
    func isSpeaking(positionMs: Int) -> Bool {
        guard let transcript else { return false }
        let time = positionMs - offsetMs
        guard let word = Self.lastIndex(in: transcript.startsMs, atMost: time) else { return false }
        if time <= transcript.endsMs[word] { return true }
        guard word + 1 < transcript.startsMs.count else { return false }
        return transcript.startsMs[word + 1] - transcript.endsMs[word] <= Self.speechGapMs
    }

    /// The next playback time, after `positionMs`, at which the active word or
    /// the speaking state can change. `nil` when nothing can change again.
    /// The clock sleeps until this time rather than polling each frame.
    func nextBoundaryMs(afterPositionMs positionMs: Int) -> Int? {
        guard let transcript else { return nil }
        let time = positionMs - offsetMs
        var candidates: [Int] = []
        let current = Self.lastIndex(in: transcript.startsMs, atMost: time)
        let nextWord = (current ?? -1) + 1
        if nextWord < transcript.startsMs.count {
            candidates.append(transcript.startsMs[nextWord])
        }
        if let current {
            let pauseAt = transcript.endsMs[current] + Self.speechGapMs
            if pauseAt > time { candidates.append(pauseAt) }
        }
        guard let soonest = candidates.min() else { return nil }
        return soonest + offsetMs
    }

    /// The last element of a sorted array that is `<= target`, found by binary search.
    private static func lastIndex(in sorted: [Int], atMost target: Int) -> Int? {
        var low = 0
        var high = sorted.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if sorted[middle] <= target {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }
}
