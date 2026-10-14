import Foundation

/// Ports `lib/views/subscription/widgets/plan_copy.dart`: price / GST / free
/// trial wording. Strings come from the Flutter l10n ARB (`app_localizations_en`).
enum PlanCopy {
    /// A plan's free period (`FreeTrial` in `subscription_plan_model.dart`).
    /// `SubscriptionPlan` has no free-trial field natively yet, so
    /// `trial(for:)` returns nil until the domain model gains it.
    struct FreeTrial: Equatable {
        let months: Int
        let days: Int
    }

    static func trial(for plan: SubscriptionPlan) -> FreeTrial? { nil }

    // MARK: Free trial

    static func plural(_ count: Int, one: String, other: String) -> String {
        count == 1 ? one : "\(count) \(other)"
    }

    static func freeTrialPeriod(_ trial: FreeTrial) -> String {
        var parts: [String] = []
        if trial.months > 0 { parts.append(count(trial.months, "Month")) }
        if trial.days > 0 {
            if trial.days % 7 == 0 {
                parts.append(count(trial.days / 7, "Week"))
            } else {
                parts.append(count(trial.days, "Day"))
            }
        }
        return parts.joined(separator: " + ")
    }

    private static func count(_ value: Int, _ unit: String) -> String {
        value == 1 ? "1 \(unit)" : "\(value) \(unit)s"
    }

    static func freeTrialHeadline(_ trial: FreeTrial) -> String {
        "\(freeTrialPeriod(trial)) Free"
    }

    // MARK: Currency / GST

    static func currencySymbol(_ currency: String) -> String {
        switch currency.trimmingCharacters(in: .whitespaces).uppercased() {
        case "INR", "RS", "RS.", "\u{20B9}": return "\u{20B9}"
        case "USD": return "$"
        case "EUR": return "\u{20AC}"
        case "GBP": return "\u{00A3}"
        default:
            let code = currency.trimmingCharacters(in: .whitespaces).uppercased()
            return code.isEmpty ? "" : "\(code) "
        }
    }

    static let gstRatePercent: Double = 18

    static func chargesGst(_ currency: String) -> Bool {
        currencySymbol(currency) == "\u{20B9}"
    }

    static func gstIncluded(_ amount: Double) -> Double {
        amount * gstRatePercent / (100 + gstRatePercent)
    }

    static func basePrice(_ amount: Double) -> Double {
        let tax = (gstIncluded(amount) * 100).rounded() / 100
        return amount - tax
    }

    /// "₹20", "₹29.50".
    static func formatPrice(_ amount: Double, currency: String) -> String {
        let whole = amount == amount.rounded()
        return currencySymbol(currency) + String(format: whole ? "%.0f" : "%.2f", amount)
    }

    /// Always two decimals ("₹0.00").
    static func formatAmount(_ amount: Double, currency: String) -> String {
        currencySymbol(currency) + String(format: "%.2f", amount)
    }
}
