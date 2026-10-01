import Foundation

/// A verse's highlight color, whole-verse granularity only (T54's scope
/// cut — see `BibleRepository.syncHighlight`'s doc comment). The wire's
/// `highlights` array can in principle carry a per-range `text` and word
/// indices; T54 never sends or reads those, so only the one color this
/// feature needs is modeled here.
struct VerseHighlight: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let verseId: String
    let colorHex: String
}
