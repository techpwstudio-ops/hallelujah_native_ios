import Foundation
import Testing
@testable import Hallelujah

struct OfferingTests {
    private func body(_ rows: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["data": rows])
    }

    @Test func parsesAUsableRow() throws {
        let offering = try #require(Offering(json: [
            "id": "o1", "amount": "199.00", "currency": "inr", "productId": "tip_199",
            "label": " Cheers ", "isPopular": true,
        ]))
        #expect(offering.id == "o1")
        #expect(offering.amount == 199)
        #expect(offering.currency == "INR")
        #expect(offering.productID == "tip_199")
        #expect(offering.label == "Cheers")
        #expect(offering.isPopular)
    }

    @Test func numericAmountAndMissingOptionalsRead() throws {
        let offering = try #require(Offering(json: ["id": "o1", "amount": 99, "productId": "tip_99"]))
        #expect(offering.amount == 99)
        #expect(offering.currency == "INR")
        #expect(offering.label == nil)
        #expect(!offering.isPopular)
    }

    @Test func unusableRowsAreNil() {
        #expect(Offering(json: ["amount": 1, "productId": "tip_1"]) == nil)
        #expect(Offering(json: ["id": "o", "amount": 1]) == nil)
        #expect(Offering(json: ["id": "o", "amount": 0, "productId": "tip_1"]) == nil)
        #expect(Offering(json: ["id": "o", "amount": "abc", "productId": "tip_1"]) == nil)
        #expect(Offering(json: "nope") == nil)
    }

    @Test func parseListDropsBadRowsAndKeepsServerOrder() {
        let list = Offering.parseList(body([
            ["id": "b", "amount": 499, "productId": "tip_499"],
            ["id": "bad", "amount": -1, "productId": "tip_x"],
            ["id": "a", "amount": 99, "productId": "tip_99"],
        ]))
        #expect(list.map(\.id) == ["b", "a"])
    }

    @Test func parseListOfAnyOtherShapeIsEmpty() {
        #expect(Offering.parseList(Data("[]".utf8)).isEmpty)
        #expect(Offering.parseList(Data("not json".utf8)).isEmpty)
        #expect(Offering.parseList(Data(#"{"data": "x"}"#.utf8)).isEmpty)
    }

    @Test func priceLabelDropsWholeDecimalsAndFallsBackToCode() {
        #expect(Offering(id: "1", amount: 199, currency: "INR", productID: "tip_1").priceLabel == "₹199")
        #expect(Offering(id: "1", amount: 49.5, currency: "INR", productID: "tip_1").priceLabel == "₹49.50")
        #expect(Offering(id: "1", amount: 5, currency: "USD", productID: "tip_1").priceLabel == "$5")
        #expect(Offering(id: "1", amount: 5, currency: "AED", productID: "tip_1").priceLabel == "AED 5")
    }

    @Test func initialSelectionPrefersPopularElseFirst() {
        let a = Offering(id: "a", amount: 99, currency: "INR", productID: "tip_99")
        let b = Offering(id: "b", amount: 199, currency: "INR", productID: "tip_199", isPopular: true)
        #expect(Offering.initialSelection(in: [a, b]) == b)
        #expect(Offering.initialSelection(in: [a]) == a)
        #expect(Offering.initialSelection(in: []) == nil)
    }

    @Test func tipProductsAreRecognisedByPrefix() {
        #expect(TipProducts.isTipProduct("tip_199"))
        #expect(!TipProducts.isTipProduct("premium_monthly"))
    }
}
