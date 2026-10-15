import Foundation

/// A page of server-paginated content. Shape grounded in the V2 home feed's
/// own `meta` envelope (`HOME_V2_API.md` §3.2: `page`/`perPage`/`total`/
/// `totalPages`/`hasMore`) — the authoritative wire contract, which carries
/// two more fields than `HomeV2Section.hydrated()` (`lib/models/
/// home_v2_section.dart`) keeps: Dart's own parse only reads `page`/
/// `totalPages`/`hasMore` because that's all its Realm-backed rail state
/// needs, not because the other two aren't sent. Kept here since a
/// "see all"/pagination footer ("12 of 340") is a reasonable thing for this
/// rewrite to show that Dart's model can't.
struct Paginated<Item: Sendable>: Sendable {
    let items: [Item]
    let page: Int
    let perPage: Int?
    let total: Int?
    let totalPages: Int
    let hasMore: Bool
    /// Opaque token for cursor-paginated lists (AI chat messages); `nil` for
    /// page-number lists.
    var nextCursor: String? = nil

    static var empty: Self { Paginated(items: [], page: 1, perPage: nil, total: nil, totalPages: 1, hasMore: false) }
}

extension Paginated: Equatable where Item: Equatable {}
