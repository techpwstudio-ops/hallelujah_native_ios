import Foundation
import Testing
@testable import GHallelujah

struct PendingTipOrderStoreTests {
    private let kv = InMemoryKeyValueStore()
    private var store: KeyValuePendingTipOrderStore { KeyValuePendingTipOrderStore(store: kv) }

    @Test func savedOrderIsReadBackAndCleared() {
        let order = PendingTipOrder(orderId: "ord_1", productId: "tip_199")
        store.save(order)
        #expect(store.read() == order)
        store.clear()
        #expect(store.read() == nil)
    }

    @Test func newTipReplacesThePendingOne() {
        store.save(PendingTipOrder(orderId: "ord_1", productId: "tip_99"))
        store.save(PendingTipOrder(orderId: "ord_2", productId: "tip_199"))
        #expect(store.read()?.orderId == "ord_2")
    }

    @Test func damagedOrIncompleteEntryReadsAsNothingPending() {
        kv.setData(Data("garbage".utf8), forKey: "tip_pending_order")
        #expect(store.read() == nil)
        store.save(PendingTipOrder(orderId: "", productId: "tip_99"))
        #expect(store.read() == nil)
    }
}
