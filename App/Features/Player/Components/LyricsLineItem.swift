import SwiftUI

/// Ports `LyricsLineItem` (`lib/widgets/player/lyrics_line_item.dart`): one
/// centred transcript line, `titleMedium` w700 / 1.4 height; active and past
/// lines white, future lines white @ 38%; the active line scales to 1.06 and
/// colours animate over 280 ms easeOutCubic. Padding 12 x 8. With `wordTiming`,
/// the active line highlights the word being said (`ActiveLyricsLine`).
struct LyricsLineItem: View {
    let text: String
    let isActive: Bool
    let isPast: Bool
    var wordTiming: WordTiming?
    var onTap: (() -> Void)?

    /// When a line is said and how to read the playhead, for the word highlight.
    struct WordTiming {
        let startMs: Int
        let endMs: Int
        let readPositionMs: @MainActor () -> Int

        /// The timing of `lines[index]`, which ends where the next line starts when its own end
        /// is missing or runs past it.
        static func of(_ lines: [LyricsTranscript], at index: Int,
                       readPositionMs: @escaping @MainActor () -> Int) -> WordTiming {
            let line = lines[index]
            let next = lines.indices.contains(index + 1) ? lines[index + 1].startTime : nil
            return WordTiming(
                startMs: CaptionWordTiming.milliseconds(line.startTime),
                endMs: CaptionWordTiming.lyricsLineEndMs(startTime: line.startTime, endTime: line.endTime,
                                                         nextLineStart: next),
                readPositionMs: readPositionMs
            )
        }
    }

    static let easeOutCubic = Animation.timingCurve(0.215, 0.61, 0.355, 1.0, duration: 0.28)

    var body: some View {
        lineText
            .typography(PlayerStyle.lyricsLine)
            .multilineTextAlignment(.center)
            .foregroundStyle(isActive || isPast ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.38))
            .frame(maxWidth: .infinity)
            .scaleEffect(isActive ? 1.06 : 1.0)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .animation(Self.easeOutCubic, value: isActive)
            .animation(Self.easeOutCubic, value: isPast)
    }

    @ViewBuilder private var lineText: some View {
        if isActive, let wordTiming {
            ActiveLyricsLine(text: text, startMs: wordTiming.startMs, endMs: wordTiming.endMs,
                             readPositionMs: wordTiming.readPositionMs)
        } else {
            Text(text)
        }
    }
}

/// The line being said, highlighted word by word. Mirrors `ActiveLyricsLine` in Flutter's
/// `lyrics_line_item.dart`.
///
/// A lyrics line carries only its start and end, so each word gets a share of that time by how long
/// it takes to say (`CaptionWordTiming.spreadLineOverWords`): syllables, and a pause after
/// punctuation. Words already said are white, the word being said is gold, and the rest are dimmed,
/// as on the transcript screen.
///
/// The engine's `currentPosition` moves only every half second, too coarse for words, so this reads
/// the playhead itself and sleeps until the next word starts. Only the active line runs the loop,
/// and the text redraws only when the word changes.
struct ActiveLyricsLine: View {
    let text: String
    let startMs: Int
    let endMs: Int
    let readPositionMs: @MainActor () -> Int

    /// The longest the loop sleeps, so a seek or a pause inside the line is caught soon.
    static let maxWaitMs = 200

    @State private var activeWord = -1

    private var words: [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var body: some View {
        Text(Self.coloured(words, activeWord: activeWord))
            .task(id: "\(startMs)-\(endMs)-\(text)") { await follow() }
    }

    private func follow() async {
        let times = CaptionWordTiming.spreadLineOverWords(words, startMs: startMs, endMs: endMs)
        guard !times.isEmpty else { return }
        while !Task.isCancelled {
            let position = readPositionMs()
            let word = Self.wordIndex(at: position, in: times)
            if word != activeWord { activeWord = word }
            let nextStart = times.indices.contains(word + 1) ? times[word + 1].start : nil
            let wait = nextStart.map { min(max($0 - position, 20), Self.maxWaitMs) } ?? Self.maxWaitMs
            try? await Task.sleep(for: .milliseconds(wait))
        }
    }

    /// The last word that has started by `positionMs`; -1 before the first word.
    static func wordIndex(at positionMs: Int, in times: [(start: Int, end: Int)]) -> Int {
        var found = -1
        for (index, time) in times.enumerated() {
            guard time.start <= positionMs else { break }
            found = index
        }
        return found
    }

    /// The line's words, spaced, each in its colour: said, being said (gold), or still to come.
    static func coloured(_ words: [String], activeWord: Int) -> AttributedString {
        var text = AttributedString()
        for (index, word) in words.enumerated() {
            var piece = AttributedString(index + 1 < words.count ? word + " " : word)
            piece.foregroundColor = TranscriptWordColor.color(spoken: index < activeWord, active: index == activeWord)
            text += piece
        }
        return text
    }
}

/// `CustomShadedMask` (`lib/widgets/widgets.dart`): fades the first and last
/// 2% of a scrolling list.
struct LyricsEdgeFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.02),
                .init(color: .black, location: 0.98),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
