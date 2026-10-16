import Foundation

/// The backend order behind a tip whose store payment has been started and not
/// yet accepted by the backend (`lib/services/pending_tip_order.dart`).
///
/// A tip is two steps — the backend creates an order, then the store takes the
/// payment — and StoreKit redelivers an unfinished transaction at every launch.
/// Verifying it needs the order id, so the id outlives the process until the
/// backend has said yes.
struct PendingTipOrder: Codable, Sendable, Equatable {
    let orderId: String
    /// The store product the order was priced for; a purchase is matched to its
    /// order by this.
    let productId: String
}

/// Where the one pending order is kept. Only the latest order is held: a new
/// tip replaces whatever was there.
protocol PendingTipOrderStore: Sendable {
    func read() -> PendingTipOrder?
    func save(_ order: PendingTipOrder)
    func clear()
}

struct KeyValuePendingTipOrderStore: PendingTipOrderStore {
    private static let key = "tip_pending_order"
    let store: any KeyValueStoring

    /// A damaged entry reads as "nothing pending" instead of throwing.
    func read() -> PendingTipOrder? {
        guard let data = store.data(forKey: Self.key),
              let order = try? JSONDecoder().decode(PendingTipOrder.self, from: data),
              !order.orderId.isEmpty, !order.productId.isEmpty
        else { return nil }
        return order
    }

    func save(_ order: PendingTipOrder) {
        store.setData(try? JSONEncoder().encode(order), forKey: Self.key)
    }

    func clear() {
        store.removeValue(forKey: Self.key)
    }
}
