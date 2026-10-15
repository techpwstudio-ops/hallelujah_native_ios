import SwiftUI

/// Plan-page widgets ported from `lib/views/subscription/widgets/*`
/// (`plans_hero.dart`, `plan_option_card.dart`, `plans_actions.dart`,
/// `payment_summary_card.dart`).

// MARK: - Hero

struct PlansHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Worship Without ").foregroundStyle(AccountParity.white70)
                + Text("Interruptions").foregroundStyle(AccountParity.white))
                .font(AccountParity.font(28, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: Dimens.spacing12)
            Text("Go ad-free, enjoy high-quality audio, offline downloads and more.")
                .font(AccountParity.bodyLarge)
                .lineSpacing(16 * 0.5)
                .foregroundStyle(AccountParity.white70)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: Dimens.spacing24)
            HStack(alignment: .top, spacing: 0) {
                feature("speaker.slash.fill", "Ad-free listening", nil)
                feature("waveform", "High-quality audio", "(Up to 320 kbps)")
                feature("arrow.down.circle.fill", "Download for offline", nil)
                feature("star.fill", "Early access to new features", nil)
            }
        }
    }

    private func feature(_ icon: String, _ label: String, _ note: String?) -> some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: Dimens.iconSize - 4))
                .foregroundStyle(AccountParity.white)
                .frame(width: Dimens.spacing48, height: Dimens.spacing48)
                .background(Circle().fill(AccountParity.fill))
                .overlay(Circle().strokeBorder(AccountParity.white12, lineWidth: 1))
            Spacer().frame(height: Dimens.spacing8)
            Text(label)
                .font(AccountParity.font(12, .medium))
                .lineSpacing(6)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            if let note {
                Text(note)
                    .font(AccountParity.font(10))
                    .foregroundStyle(AccountParity.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Dimens.spacing2)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// App-bar title: Premium mark + "Hallelujah Premium".
struct PlansAppBarTitle: View {
    var body: some View {
        HStack(spacing: Dimens.spacing8) {
            Image(systemName: "rosette")
                .font(.system(size: Dimens.iconSizeSmall + 2))
                .foregroundStyle(AccountParity.white)
            Text("Hallelujah Premium")
                .font(AccountParity.titleMedium)
                .foregroundStyle(AccountParity.white)
        }
    }
}

// MARK: - Plan card

struct PlanPill: View {
    let label: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(label)
            .font(AccountParity.font(12, .bold))
            .tracking(0.1)
            .foregroundStyle(foreground)
            .padding(.horizontal, Dimens.spacing12)
            .padding(.vertical, Dimens.spacing4)
            .background(Capsule().fill(background))
    }
}

struct PlanOptionCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void

    /// `ColorTheme.accentFill` / `accentSurface`.
    static let accentFill = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x23 / 255)
    static let accentSurface = Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x2E / 255)

    private var isIndividual: Bool { plan.maxMembers <= 1 }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                Image(systemName: isIndividual ? "person.fill" : "person.2.fill")
                    .font(.system(size: Dimens.iconSize - 4))
                    .foregroundStyle(AccountParity.white)
                    .frame(width: Dimens.spacing48, height: Dimens.spacing48)
                    .background(
                        RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                            .fill(Self.accentSurface)
                    )
                Spacer().frame(width: Dimens.spacing16)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Dimens.spacing8) {
                        Text(plan.name)
                            .font(AccountParity.font(20, .bold))
                            .foregroundStyle(AccountParity.white)
                        if isCurrent {
                            PlanPill(label: "Current Plan", background: AccountParity.white12, foreground: AccountParity.white)
                        }
                    }
                    Text(isIndividual ? "Music just for you" : "Music for your family")
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(AccountParity.white70)
                    Spacer().frame(height: Dimens.spacing8)
                    priceBlock
                    if plan.maxMembers > 1 {
                        Spacer().frame(height: Dimens.spacing8)
                        PlanPill(
                            label: "Up to \(plan.maxMembers) members",
                            background: Self.accentSurface,
                            foreground: AccountParity.white70
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: Dimens.spacing12)
                indicator
            }
            .padding(Dimens.paddingLarge)
            .modifier(PlanCardSurface(isSelected: isSelected, unselectedFill: AccountParity.fill))
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(isSelected ? AccountParity.white : AccountParity.white12, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var priceBlock: some View {
        let currency = plan.currency ?? ""
        if let price = plan.price {
            let text = PlanCopy.formatPrice(price, currency: currency)
            if let trial = PlanCopy.trial(for: plan) {
                PlanPill(label: PlanCopy.freeTrialHeadline(trial), background: AccountParity.white, foreground: AccountParity.black)
                Spacer().frame(height: Dimens.spacing8)
                Text("Then \(text) / Month")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white70)
            } else {
                Text("\(text) / Month")
                    .font(AccountParity.font(16, .bold))
                    .foregroundStyle(AccountParity.white)
            }
        }
    }

    private var indicator: some View {
        ZStack {
            Circle().fill(isSelected ? AccountParity.white : Color.clear)
            Circle().strokeBorder(isSelected ? AccountParity.white : AccountParity.white24, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AccountParity.black)
            }
        }
        .frame(width: Dimens.spacing28, height: Dimens.spacing28)
    }
}

// MARK: - Summary

struct PaymentSummaryCard: View {
    let plan: SubscriptionPlan

    var body: some View {
        let currency = plan.currency ?? ""
        let price = plan.price ?? 0
        let trial = PlanCopy.trial(for: plan)
        let period = trial.map { PlanCopy.freeTrialPeriod($0) }
        let periodText = period ?? ""
        let chargedToday: Double = trial == nil ? price : 0
        let payableToday = PlanCopy.formatAmount(chargedToday, currency: currency)
        let monthly = PlanCopy.formatPrice(price, currency: currency)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Dimens.spacing12) {
                Image(systemName: "receipt")
                    .font(.system(size: Dimens.iconSize - 4))
                    .foregroundStyle(AccountParity.white)
                    .frame(width: Dimens.spacing40, height: Dimens.spacing40)
                    .background(
                        RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                            .fill(PlanOptionCard.accentSurface)
                    )
                Text("Payment Summary")
                    .font(AccountParity.font(16, .bold))
                    .foregroundStyle(AccountParity.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(height: Dimens.spacing16)
            summaryRow(
                "Plan",
                trial == nil ? plan.name : "\(plan.name) (\(PlanCopy.freeTrialHeadline(trial!)))"
            )
            if let period {
                Spacer().frame(height: Dimens.spacing8)
                summaryRow("Due today", payableToday)
                Spacer().frame(height: Dimens.spacing8)
                summaryRow("\(period) free trial", PlanCopy.formatAmount(0, currency: currency))
            }
            if PlanCopy.chargesGst(currency) {
                Spacer().frame(height: Dimens.spacing8)
                summaryRow("Base price", PlanCopy.formatAmount(PlanCopy.basePrice(chargedToday), currency: currency))
                Spacer().frame(height: Dimens.spacing8)
                summaryRow("Tax", PlanCopy.formatAmount(PlanCopy.gstIncluded(chargedToday), currency: currency))
            }
            Rectangle().fill(AccountParity.white12).frame(height: 1)
                .padding(.vertical, Dimens.spacing12)
            HStack {
                Text("Payable today")
                    .font(AccountParity.font(16, .bold))
                    .foregroundStyle(AccountParity.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(payableToday)
                    .font(AccountParity.font(24, .bold))
                    .foregroundStyle(AccountParity.white)
            }
            Spacer().frame(height: Dimens.spacing12)
            HStack(alignment: .top, spacing: Dimens.spacing8) {
                Image(systemName: "info.circle")
                    .font(.system(size: Dimens.iconSizeSmall + 2))
                    .foregroundStyle(AccountParity.white70)
                Text(period == nil
                    ? "You'll be charged \(monthly) per month. Cancel anytime before renewal."
                    : "Free for \(periodText), then \(monthly) per month. Cancel anytime.")
                    .font(AccountParity.bodySmall)
                    .lineSpacing(6)
                    .foregroundStyle(AccountParity.white70)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Dimens.spacing12)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                    .fill(AccountParity.black)
            )
        }
        .padding(Dimens.paddingLarge)
        .background(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                .fill(AccountParity.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous)
                .strokeBorder(AccountParity.white12, lineWidth: 1)
        )
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Dimens.spacing12) {
            Text(label)
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white70)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Actions

/// `PlansCtaButton`: white -> DDDDDD pill, label + arrow, 0.4 opacity when disabled.
struct PlansCtaButton: View {
    let label: String
    var isLoading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Dimens.spacing8) {
                if isLoading {
                    ProgressView().tint(AccountParity.black)
                } else {
                    Text(label)
                        .font(AccountParity.font(14, .semibold))
                        .foregroundStyle(AccountParity.black)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: Dimens.spacing16, weight: .regular))
                        .foregroundStyle(AccountParity.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Dimens.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusELarge, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white, Color(red: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Terms of Use | Privacy Policy | Restore Purchases (restore only when given).
struct PlansFooterLinks: View {
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    var onRestore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            link("Terms of Use", onTerms)
            divider
            link("Privacy Policy", onPrivacy)
            if let onRestore {
                divider
                link("Restore Purchases", onRestore)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(AccountParity.white24).frame(width: 1, height: 12)
    }

    private func link(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AccountParity.bodySmall)
                .underline(true, color: Color.white.opacity(0.38))
                .foregroundStyle(AccountParity.white70)
                .padding(.horizontal, Dimens.spacing8)
                .padding(.vertical, Dimens.spacing8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expandable text

private struct ExpandableHeightKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// `ExpandableText` (`verse_unit_ui.dart`): `maxLines` lines with an ellipsis
/// and a bold "Read more" / "Read less" link only when the text overflows.
struct ParityExpandableText: View {
    let text: String
    var font: Font = AccountParity.bodySmall
    var color: Color = AccountParity.tertiaryText
    var maxLines: Int = 3
    var lineSpacing: CGFloat = 6

    @State private var expanded = false
    @State private var heights: [Int: CGFloat] = [:]

    private var overflows: Bool {
        guard let limited = heights[0], let full = heights[1] else { return false }
        return full > limited + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
                .foregroundStyle(color)
                .lineLimit(expanded ? nil : maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
            if overflows {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Read less" : "Read more")
                        .font(font.bold())
                        .foregroundStyle(color)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .background(measure)
        .onPreferenceChange(ExpandableHeightKey.self) { heights = $0 }
    }

    private var measure: some View {
        ZStack {
            Text(text).font(font).lineSpacing(lineSpacing).lineLimit(maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { Color.clear.preference(key: ExpandableHeightKey.self, value: [0: $0.size.height]) })
            Text(text).font(font).lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { Color.clear.preference(key: ExpandableHeightKey.self, value: [1: $0.size.height]) })
        }
        .hidden()
        .allowsHitTesting(false)
    }
}

/// Selected plan card floats on interactive glass; unselected stays flat.
private struct PlanCardSurface: ViewModifier {
    let isSelected: Bool
    let unselectedFill: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.glassRounded(Dimens.cornerRadiusLarge, interactive: true)
        } else {
            content.background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusLarge, style: .continuous).fill(unselectedFill)
            )
        }
    }
}
