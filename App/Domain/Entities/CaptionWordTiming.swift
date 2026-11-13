import Foundation

/// Better word timing for transcripts that came from captions. Mirrors
/// `lib/features/podcast/data/word_timing.dart` in the Flutter app; keep the
/// two in step so both apps highlight the same word at the same moment.
///
/// Most transcripts reach us as captions (VTT, SRT, Podcast 2.0 JSON): a line
/// of text with one start and one end. The server spreads each line's time over
/// its words in proportion to their length in characters (`cueWords.js`). That
/// is noticeably off as you listen: a long word with few sounds ("through") is
/// held too long and a short one ("I") flashes past; Telugu and Hindi words are
/// counted by code point, so every vowel sign and virama makes a word look
/// longer than it sounds; and the pause at a comma or full stop is smeared over
/// the words, so the highlight runs ahead of the voice through every clause.
///
/// `refine` finds the lines that were spread that way and spreads each again by
/// an estimate of how long each word takes to say: syllables for Latin script,
/// spoken vowels (aksharas) for Indian scripts, one beat per digit, a small
/// fixed cost per word, and a pause after punctuation. Each line keeps its exact
/// start and end from the caption. Real word timing (speech to text) is left
/// exactly as it is.
enum CaptionWordTiming {
    /// Fixed cost of any word, in syllable beats.
    static let wordBeat = 0.35
    /// Pause after a word ending in , ; : or a dash, in beats.
    static let shortPauseBeats = 0.6
    /// Pause after a word ending a sentence (. ! ? … । ॥), in beats.
    static let longPauseBeats = 1.2

    /// How far a boundary may sit from the server's character split and still
    /// be read as that split (whole-ms rounding, unknown line end while growing).
    private static let fitToleranceMs = 2
    /// A file is re-timed only when at least this share of its words sit in
    /// caption lines of three or more words; below it, it is real timing.
    private static let minCaptionShare = 0.5
    /// Longest run grown into one line; bounds the work only.
    private static let maxLineWords = 80

    /// Re-spreads, in place, the words of every caption line. Each line's first
    /// start and last end are unchanged, and starts never go backwards.
    static func refine(startsMs: inout [Int], endsMs: inout [Int], words: [String]) {
        let n = words.count
        guard n >= 2, startsMs.count == n, endsMs.count == n else { return }
        let lines = captionLines(startsMs: startsMs, endsMs: endsMs, words: words)
        let covered = lines.reduce(0) { $0 + ($1.count >= 3 ? $1.count : 0) }
        guard Double(covered) >= Double(n) * minCaptionShare else { return }
        for line in lines where line.count > 1 {
            respread(startsMs: &startsMs, endsMs: &endsMs, words: words, line: line)
        }
    }

    /// The caption lines in the file as word ranges. A word in no caption line
    /// is a line of its own. A line grows while the words touch and the
    /// boundaries still match a character split of the whole run; two touching
    /// captions are told apart because their pace differs.
    static func captionLines(startsMs: [Int], endsMs: [Int], words: [String]) -> [ClosedRange<Int>] {
        var lines: [ClosedRange<Int>] = []
        let n = words.count
        var first = 0
        while first < n {
            var last = first
            while last + 1 < n,
                  last - first + 1 < maxLineWords,
                  endsMs[last] == startsMs[last + 1],
                  isCaptionLine(startsMs: startsMs, endsMs: endsMs, words: words, first: first, last: last + 1) {
                last += 1
            }
            lines.append(first...last)
            first = last + 1
        }
        return lines
    }

    private static func isCaptionLine(startsMs: [Int], endsMs: [Int], words: [String], first: Int, last: Int) -> Bool {
        let start = startsMs[first]
        let duration = endsMs[last] - start
        guard duration > 0 else { return false }
        var total = 0
        for k in first...last { total += codePoints(words[k]) }
        var consumed = 0
        for k in first..<last {
            consumed += codePoints(words[k])
            let expected = start + Int((Double(duration) * Double(consumed) / Double(total)).rounded())
            if abs(endsMs[k] - expected) > fitToleranceMs { return false }
            if startsMs[k + 1] != endsMs[k] { return false }
        }
        return true
    }

    private static func respread(startsMs: inout [Int], endsMs: inout [Int], words: [String], line: ClosedRange<Int>) {
        let start = startsMs[line.lowerBound]
        let end = endsMs[line.upperBound]
        let duration = Double(end - start)
        var beats: [Double] = []
        var pauses: [Double] = []
        var total = 0.0
        for k in line {
            let beat = spokenBeats(words[k])
            // The caption's own end already marks the pause after its last word.
            let pause = k < line.upperBound ? pauseBeats(after: words[k]) : 0
            beats.append(beat)
            pauses.append(pause)
            total += beat + pause
        }
        guard total > 0 else { return }
        var t = 0.0
        for (i, k) in line.enumerated() {
            startsMs[k] = start + Int((duration * t / total).rounded())
            t += beats[i]
            endsMs[k] = k == line.upperBound ? end : start + Int((duration * t / total).rounded())
            t += pauses[i]
        }
    }

    /// Start and end of each of `words`, spread over one line that runs from `startMs` to `endMs`,
    /// by the same estimate the caption lines use. For a lyrics line, which carries only its own
    /// start and end. Empty when the line has no words or no time. Mirrors `spreadLineOverWords`.
    static func spreadLineOverWords(_ words: [String], startMs: Int, endMs: Int) -> [(start: Int, end: Int)] {
        guard !words.isEmpty, endMs > startMs else { return [] }
        var starts = Array(repeating: startMs, count: words.count)
        var ends = Array(repeating: endMs, count: words.count)
        respread(startsMs: &starts, endsMs: &ends, words: words, line: 0...(words.count - 1))
        return zip(starts, ends).map { (start: $0, end: $1) }
    }

    /// When a lyrics line stops being said, in milliseconds. Its own end when that is after its
    /// start, cut at the next line's start; otherwise the next line's start; otherwise a few seconds,
    /// so a line with no end still moves. Mirrors `lyricsLineEndMs` in `lyrics_line_item.dart`.
    static func lyricsLineEndMs(startTime: Double, endTime: Double, nextLineStart: Double?) -> Int {
        let startMs = milliseconds(startTime)
        let nextMs = nextLineStart.map(milliseconds)
        var endMs = milliseconds(endTime)
        if endMs <= startMs { endMs = nextMs ?? startMs + fallbackLineMs }
        if let nextMs, nextMs > startMs, nextMs < endMs { endMs = nextMs }
        if endMs <= startMs { endMs = startMs + fallbackLineMs }
        return endMs
    }

    /// How long a lyrics line with no usable end is highlighted for.
    static let fallbackLineMs = 4000

    static func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }

    private static func codePoints(_ word: String) -> Int {
        max(word.unicodeScalars.count, 1)
    }

    /// How long `word` takes to say, in syllable beats.
    static func spokenBeats(_ word: String) -> Double {
        let scalars = Array(word.unicodeScalars)
        var indic = 0
        var digits = 0
        var otherLetters = 0
        var latin = ""
        var lastBareConsonantBlock: UInt32?

        var i = 0
        while i < scalars.count {
            let cp = scalars[i].value
            if (0x0900...0x0DFF).contains(cp) {
                let block = cp & ~0x7F
                let offset = cp & 0x7F
                if isIndependentVowel(offset) {
                    indic += 1
                    lastBareConsonantBlock = nil
                } else if isConsonant(offset) {
                    var j = i + 1
                    if j < scalars.count, scalars[j].value == block + 0x3C { j += 1 } // nukta
                    let hasVirama = j < scalars.count && scalars[j].value == block + 0x4D
                    if !hasVirama {
                        indic += 1
                        let hasVowelSign = j < scalars.count && isVowelSign(scalars[j].value)
                        lastBareConsonantBlock = hasVowelSign ? nil : block
                    }
                } else if isVowelSign(cp) {
                    lastBareConsonantBlock = nil
                }
            } else if (0x30...0x39).contains(cp) {
                digits += 1
            } else if isLatinLetter(cp) {
                latin.unicodeScalars.append(scalars[i])
            } else if scalars[i].properties.isAlphabetic {
                otherLetters += 1
            }
            i += 1
        }

        // Hindi, Bengali, Punjabi and Gujarati drop the inherent vowel of a
        // final bare consonant: "हम" is one syllable, not two.
        if indic > 1, let block = lastBareConsonantBlock, dropsFinalVowel(block) {
            indic -= 1
        }
        let syllables = latin.isEmpty ? 0 : latinSyllables(latin)
        let spoken = Double(indic + syllables + digits) + Double(otherLetters) * 0.5
        return wordBeat + spoken
    }

    /// The pause after `word`, in beats, from its closing punctuation.
    static func pauseBeats(after word: String) -> Double {
        var trimmed = Substring(word)
        while let last = trimmed.last, "\"'”’»)]".contains(last) { trimmed = trimmed.dropLast() }
        guard let last = trimmed.last else { return 0 }
        if ".!?…।॥".contains(last) { return longPauseBeats }
        if ",;:—–-".contains(last) { return shortPauseBeats }
        return 0
    }

    private static func isIndependentVowel(_ offset: UInt32) -> Bool {
        (0x05...0x14).contains(offset) || offset == 0x60 || offset == 0x61
    }

    private static func isConsonant(_ offset: UInt32) -> Bool {
        (0x15...0x39).contains(offset) || (0x58...0x5F).contains(offset)
    }

    private static func isVowelSign(_ cp: UInt32) -> Bool {
        guard (0x0900...0x0DFF).contains(cp) else { return false }
        let offset = cp & 0x7F
        return (0x3E...0x4C).contains(offset) || offset == 0x62 || offset == 0x63
    }

    private static func dropsFinalVowel(_ block: UInt32) -> Bool {
        block == 0x0900 || block == 0x0980 || block == 0x0A00 || block == 0x0A80
    }

    private static func isLatinLetter(_ cp: UInt32) -> Bool {
        (0x41...0x5A).contains(cp) || (0x61...0x7A).contains(cp)
            || ((0xC0...0x24F).contains(cp) && cp != 0xD7 && cp != 0xF7)
    }

    /// Vowel groups, less a silent final "e".
    private static func latinSyllables(_ word: String) -> Int {
        let w = Array(word.lowercased().unicodeScalars).map(\.value)
        var groups = 0
        var previousVowel = false
        for c in w {
            let vowel = isLatinVowel(c)
            if vowel && !previousVowel { groups += 1 }
            previousVowel = vowel
        }
        let n = w.count
        if groups > 1, n > 2, w[n - 1] == 0x65, w[n - 2] != 0x6C, !isLatinVowel(w[n - 2]) {
            groups -= 1
        }
        return max(groups, 1)
    }

    private static func isLatinVowel(_ c: UInt32) -> Bool {
        c == 0x61 || c == 0x65 || c == 0x69 || c == 0x6F || c == 0x75 || c == 0x79
            || (0xE0...0xE6).contains(c) || (0xE8...0xEF).contains(c)
            || (0xF2...0xF6).contains(c) || (0xF9...0xFC).contains(c)
    }
}
