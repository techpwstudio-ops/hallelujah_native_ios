import Foundation

/// One heading in the credits sheet and the credits under it.
struct SongCreditGroup: Sendable, Equatable {
    let category: String
    let credits: [SongCredit]
}

extension [SongCredit] {
    /// Heading used for credits that arrive without a category.
    static var uncategorizedHeading: String { "Others" }

    /// `groupCreditsByCategory` (`SongRepositoryModel.dart`): credits grouped
    /// under their `category` (blank → "Others"), headings in order of first
    /// appearance — Dart's `Map` iterates in insertion order, and the sheet
    /// renders it in that order.
    func groupedByCategory() -> [SongCreditGroup] {
        var order: [String] = []
        var buckets: [String: [SongCredit]] = [:]
        for credit in self {
            let trimmed = credit.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let heading = trimmed.isEmpty ? Self.uncategorizedHeading : trimmed
            if buckets[heading] == nil { order.append(heading) }
            buckets[heading, default: []].append(credit)
        }
        return order.map { SongCreditGroup(category: $0, credits: buckets[$0] ?? []) }
    }
}
