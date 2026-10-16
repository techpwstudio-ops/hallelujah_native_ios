import SwiftUI

/// A wrapping row layout that stops after `maxRows` rows and ends the last one
/// with a "more" view (`lib/widgets/ui/clamped_wrap.dart`, `ai` branch).
///
/// The LAST subview is the "more" view when `hasMore` is true; every subview
/// before it is an item. How many items fit in a row depends on their measured
/// widths, so the cut is made during layout. Items that don't fit (and the
/// "more" view once `expanded`, or when everything already fits) are placed
/// far outside the bounds; pair with `.clipped()` so they are neither seen nor
/// hit-tested.
struct ClampedWrapLayout: Layout {
    var maxRows: Int
    var expanded: Bool
    var hasMore: Bool
    var spacing: CGFloat = 0
    var runSpacing: CGFloat = 0

    private static let hidden = CGPoint(x: -10_000, y: -10_000)

    private struct Result {
        var size: CGSize
        var origins: [CGPoint]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let origin = result.origins[index]
            let point = origin == Self.hidden
                ? origin
                : CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y)
            subview.place(at: point, proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Result {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let itemCount = hasMore ? subviews.count - 1 : subviews.count
        let moreSize = hasMore ? sizes[subviews.count - 1] : .zero

        // Greedy rows over the items: each row is a list of item indices.
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for i in 0..<max(itemCount, 0) {
            let w = sizes[i].width
            if x > 0, x + w > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(i)
            x += w + spacing
        }

        var visibleRows = rows
        var showMore = false
        if hasMore, !expanded, rows.count > maxRows {
            visibleRows = Array(rows.prefix(maxRows))
            var last = visibleRows[maxRows - 1]
            // Drop items from the last row until the "more" view fits after it.
            func rowWidth(_ items: [Int]) -> CGFloat {
                items.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(items.count) + moreSize.width
            }
            while !last.isEmpty, rowWidth(last) > width { last.removeLast() }
            visibleRows[maxRows - 1] = last
            showMore = true
        }

        var origins = [CGPoint](repeating: Self.hidden, count: subviews.count)
        var y: CGFloat = 0
        var maxX: CGFloat = 0
        for (rowIndex, row) in visibleRows.enumerated() {
            var rowX: CGFloat = 0
            var rowHeight: CGFloat = 0
            for i in row {
                origins[i] = CGPoint(x: rowX, y: y)
                rowX += sizes[i].width + spacing
                rowHeight = max(rowHeight, sizes[i].height)
            }
            if showMore, rowIndex == visibleRows.count - 1 {
                origins[subviews.count - 1] = CGPoint(x: rowX, y: y)
                rowX += moreSize.width + spacing
                rowHeight = max(rowHeight, moreSize.height)
            }
            maxX = max(maxX, rowX - spacing)
            y += rowHeight + (rowIndex == visibleRows.count - 1 ? 0 : runSpacing)
        }
        return Result(size: CGSize(width: width.isFinite ? width : maxX, height: y), origins: origins)
    }
}
