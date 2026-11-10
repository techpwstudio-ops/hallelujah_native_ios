import CoreGraphics

/// Places the chapters along the seekbar track (Phase 1). Pure geometry, no
/// view code, so the rules can be tested directly.
enum ChapterSegmentLayout {
    static let defaultGap: CGFloat = 3
    static let defaultMinimumWidth: CGFloat = 6

    /// One drawn piece of the track. Chapters narrower than `minimumWidth` are
    /// merged with a neighbour, so `startSeconds`/`endSeconds` may span several chapters.
    struct Segment: Equatable, Identifiable {
        let id: Int
        let startX: CGFloat
        let width: CGFloat
        let startSeconds: Double
        let endSeconds: Double

        /// The played part of this segment at `seconds`, from 0 to 1.
        func playedFraction(at seconds: Double) -> Double {
            let length = endSeconds - startSeconds
            guard length > 0 else { return 0 }
            return min(max((seconds - startSeconds) / length, 0), 1)
        }
    }

    /// A run of consecutive chapters that is drawn as one segment.
    private struct Group {
        var firstIndex: Int
        var lastIndex: Int
        var width: CGFloat
    }

    /// Widths are proportional to chapter length, with `gap` between segments.
    /// The chapters together fill exactly `trackWidth`, so no segment is ever
    /// wider than the bar, whatever the spans say.
    ///
    /// A span with no `end` is open-ended. It ends where the next span starts,
    /// and the last one gets the average length of the others (a whole unit when
    /// it is alone). That is only a stand-in for the width until the real end is
    /// known, and it becomes the segment's `endSeconds`.
    static func segments(
        spans rawSpans: [(start: Double, end: Double?)],
        trackWidth: CGFloat,
        gap: CGFloat = defaultGap,
        minimumWidth: CGFloat = defaultMinimumWidth
    ) -> [Segment] {
        let spans = closedSpans(rawSpans)
        let totalLength = spans.reduce(0) { $0 + max($1.end - $1.start, 0) }
        guard !spans.isEmpty, totalLength > 0, trackWidth > 0 else { return [] }
        let available = max(trackWidth - gap * CGFloat(spans.count - 1), 0)
        let rawWidths = spans.map { CGFloat(max($0.end - $0.start, 0) / totalLength) * available }

        var groups: [Group] = []
        for index in spans.indices {
            if let last = groups.last, last.width < minimumWidth {
                groups[groups.count - 1] = Group(
                    firstIndex: last.firstIndex,
                    lastIndex: index,
                    width: last.width + gap + rawWidths[index]
                )
            } else {
                groups.append(Group(firstIndex: index, lastIndex: index, width: rawWidths[index]))
            }
        }
        // A short final group joins the one before it instead of standing alone.
        if groups.count > 1, let tail = groups.last, tail.width < minimumWidth {
            groups.removeLast()
            let previous = groups.removeLast()
            groups.append(Group(
                firstIndex: previous.firstIndex,
                lastIndex: tail.lastIndex,
                width: previous.width + gap + tail.width
            ))
        }

        var cursor: CGFloat = 0
        var result: [Segment] = []
        for (offset, group) in groups.enumerated() {
            result.append(Segment(
                id: offset,
                startX: cursor,
                width: group.width,
                startSeconds: spans[group.firstIndex].start,
                endSeconds: spans[group.lastIndex].end
            ))
            cursor += group.width + gap
        }
        return result
    }

    /// Gives every open-ended span an end, as `segments` describes.
    private static func closedSpans(_ spans: [(start: Double, end: Double?)]) -> [(start: Double, end: Double)] {
        let knownLengths = spans.compactMap { span in span.end.map { max($0 - span.start, 0) } }
        let average = knownLengths.isEmpty ? 1 : knownLengths.reduce(0, +) / Double(knownLengths.count)
        let standIn = average > 0 ? average : 1
        return spans.enumerated().map { offset, span in
            if let end = span.end { return (start: span.start, end: end) }
            let nextStart = offset + 1 < spans.count ? spans[offset + 1].start : nil
            return (start: span.start, end: nextStart ?? span.start + standIn)
        }
    }
}
