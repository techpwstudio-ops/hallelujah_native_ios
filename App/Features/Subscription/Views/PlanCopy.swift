import Foundation

/// Ports `lib/views/subscription/widgets/plan_copy.dart`: price / GST / free
/// trial wording. Strings come from the Flutter l10n ARB (`app_localizations_en`).
enum PlanCopy {
    /// A plan's free period (`FreeTrial` in `subscription_plan_model.dart`).
    struct FreeTrial: Equatable {
        let months: Int
        let days: Int
    }

    static func trial(for plan: SubscriptionPlan) -> FreeTrial? {
        plan.freeTrial.map { FreeTrial(months: $0.months, days: $0.days) }
    }

    // MARK: Free trial

    static func freeTrialPeriod(_ trial: FreeTrial) -> String {
        var parts: [String] = []
        if trial.months > 0 { parts.append(monthsText(trial.months)) }
        if trial.days > 0 {
            if trial.days % 7 == 0 {
                parts.append(weeksText(trial.days / 7))
            } else {
                parts.append(daysText(trial.days))
            }
        }
        return parts.joined(separator: " + ")
    }

    private static func monthsText(_ value: Int) -> String {
        value == 1 ? String(localized: "1 Month") : String(localized: "\(value) Months")
    }

    private static func weeksText(_ value: Int) -> String {
        value == 1 ? String(localized: "1 Week") : String(localized: "\(value) Weeks")
    }

    private static func daysText(_ value: Int) -> String {
        value == 1 ? String(localized: "1 Day") : String(localized: "\(value) Days")
    }

    static func freeTrialHeadline(_ trial: FreeTrial) -> String {
        String(localized: "\(freeTrialPeriod(trial)) Free")
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

    private static func isoCode(_ currency: String) -> String? {
        switch currency.trimmingCharacters(in: .whitespaces).uppercased() {
        case "INR", "RS", "RS.", "\u{20B9}": return "INR"
        case "USD": return "USD"
        case "EUR": return "EUR"
        case "GBP": return "GBP"
        default: return nil
        }
    }

    private static func formatted(_ amount: Double, currency: String, fractionDigits: Int) -> String {
        if let code = isoCode(currency) {
            return amount.formatted(.currency(code: code).precision(.fractionLength(fractionDigits)))
        }
        return currencySymbol(currency) + amount.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// "₹20", "₹29.50".
    static func formatPrice(_ amount: Double, currency: String) -> String {
        formatted(amount, currency: currency, fractionDigits: amount == amount.rounded() ? 0 : 2)
    }

    /// Always two decimals ("₹0.00").
    static func formatAmount(_ amount: Double, currency: String) -> String {
        formatted(amount, currency: currency, fractionDigits: 2)
    }
}
