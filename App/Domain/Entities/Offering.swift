import Foundation

/// One tip amount a listener can pick on the Music Player, as
/// `GET /offerings` reports it (`lib/models/offering_model.dart`, `ai` branch).
///
/// The server already scopes the list to this device's store (`os` header) and
/// to active rows, so the app never filters by platform itself. Amounts are no
/// longer hardcoded: each one is a consumable product the admin panel manages.
struct Offering: Sendable, Equatable, Identifiable {
    let id: String
    /// Display amount in `currency`. Whole amounts (99) are the usual case.
    let amount: Double
    let currency: String
    /// Store consumable product identifier for this store.
    let productID: String
    /// Short personality label shown under the amount (e.g. "Cheers").
    let label: String?
    /// The tier to pre-select when the sheet opens.
    let isPopular: Bool

    /// `Offering.tryParse`: nil when the row is unusable (no id, no product, a
    /// non-positive amount), so one malformed row never takes the list down.
    init?(json: Any) {
        guard let map = json as? [String: Any] else { return nil }
        guard let id = Self.string(map["id"]), !id.isEmpty,
              let productID = Self.string(map["productId"]), !productID.isEmpty,
              let amount = Self.string(map["amount"]).flatMap(Double.init), amount > 0
        else { return nil }
        let label = Self.string(map["label"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: id,
            amount: amount,
            currency: (Self.string(map["currency"]) ?? "INR").uppercased(),
            productID: productID,
            label: (label?.isEmpty ?? true) ? nil : label,
            isPopular: (map["isPopular"] as? Bool) == true
        )
    }

    init(id: String, amount: Double, currency: String, productID: String, label: String? = nil, isPopular: Bool = false) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.productID = productID
        self.label = label
        self.isPopular = isPopular
    }

    /// Dart's `toString()` on a JSON value: numbers and strings both read.
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static let symbols = ["INR": "₹", "USD": "$", "EUR": "€", "GBP": "£"]

    /// `₹199` or `₹49.50`. Whole amounts drop the decimals; a currency without
    /// a known symbol falls back to its code.
    var priceLabel: String {
        let value = amount == amount.rounded()
            ? String(format: "%.0f", amount)
            : String(format: "%.2f", amount)
        if let symbol = Self.symbols[currency] { return symbol + value }
        return "\(currency) \(value)"
    }

    /// Parses a `GET /offerings` body (`{data: [...]}`), skipping unusable
    /// rows. A body of any other shape is an empty list.
    static func parseList(_ data: Data) -> [Offering] {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = body["data"] as? [Any]
        else { return [] }
        return list.compactMap(Offering.init(json:))
    }

    /// The tier the sheet opens on: the server's pre-selected one, else first.
    static func initialSelection(in offerings: [Offering]) -> Offering? {
        offerings.first(where: \.isPopular) ?? offerings.first
    }
}

/// Tip product conventions (`lib/constants/tip_products.dart`, `ai` branch).
enum TipProducts {
    /// Every tip's store product id starts with this; the backend enforces it
    /// on the offerings table, so an id that doesn't can never be a tip.
    static let productIDPrefix = "tip_"

    static func isTipProduct(_ productID: String) -> Bool {
        productID.hasPrefix(productIDPrefix)
    }
}
