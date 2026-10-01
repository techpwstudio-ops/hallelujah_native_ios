import SwiftUI

/// Ports `showTipToArtistSheet` (`lib/sheets/tip/showTipDonationSheet.dart`).
/// Dumb UI, same shape as the Dart original: owns only the pending amount/
/// note while open and forwards the result through `onSend` — the caller
/// (`FullPlayerView`) wires that to `TipPurchaseManager`. Presented via
/// `.appSheet`, which already supplies its own drag handle
/// (`AppSheetContainer`), so this view draws none of its own, unlike Dart's
/// builder which draws its own `DragHandler`.
///
/// Tapping Send dismisses immediately, same as Dart's own
/// `onSend(amount, note); NavigationService.back();` — the purchase and its
/// backend round-trip continue after the sheet is gone, surfaced only via a
/// toast later (see `FullPlayerView.sendTip`).
///
/// Dart's five preset/`"More"` `ChoiceChip`s sit in a `Wrap` that only
/// exists to flow onto a second row at the sheet's fixed width; a horizontal
/// `ScrollView` (the same idiom `CreatorProfileView.tabBar` already uses for
/// a short chip row) gives the same "every option reachable" affordance
/// without a bespoke flow-layout type for five items.
///
/// `TipProducts.step` (slider granularity) has no call site in Dart's own
/// `Slider` either — its `onChanged` snaps straight to `nearestTier(value)`
/// with no `divisions:` — so it isn't ported here either, same "don't port
/// dead code" precedent `VoiceConversationScreen` already established for
/// Dart's unreachable locale picker.
struct TipDonationSheet: View {
    let artistName: String?
    let onSend: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var amount = TipProducts.defaultAmount
    @State private var showsSlider = false
    @State private var note = ""

    private let presets = TipProducts.presetAmounts
    private let minAmount = TipProducts.minAmount
    private let maxAmount = TipProducts.maxAmount

    private var title: String {
        let trimmed = artistName?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Support the Artist" : "Support \(trimmed)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                Text(title)
                    .typography(Typography.titleLarge)
                    .foregroundStyle(theme.color(.textPrimary))
                    .multilineTextAlignment(.center)

                Text("Show your appreciation for this music. Your support goes directly to the creator.")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
                    .multilineTextAlignment(.center)

                Text("₹ \(amount)")
                    .typography(Typography.headlineMedium)
                    .foregroundStyle(theme.color(.textPrimary))

                AppTextField(text: $note, placeholder: "Say Thanks")

                presetChips

                if showsSlider {
                    sliderSection
                }

                AppButton(label: "Send ₹ \(amount)") {
                    guard amount >= minAmount else { return }
                    onSend(amount, note.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }

                Text("Every contribution helps artists continue creating music.")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(theme.color(.textTertiary))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(presets, id: \.self) { preset in
                    AppChip(title: "₹ \(preset)", isSelected: amount == preset && !showsSlider) {
                        amount = preset
                        showsSlider = false
                    }
                }
                AppChip(title: "More", isSelected: showsSlider) {
                    showsSlider = true
                }
            }
        }
    }

    private var sliderSection: some View {
        VStack(spacing: Spacing.xs) {
            Slider(
                value: Binding(
                    get: { Double(amount) },
                    set: { amount = nearestTier($0) }
                ),
                in: Double(minAmount)...Double(maxAmount)
            )
            HStack {
                Text("₹ \(minAmount)")
                Spacer()
                Text("₹ \(maxAmount)")
            }
            .typography(Typography.labelSmall)
            .foregroundStyle(theme.color(.textSecondary))
        }
    }

    private func nearestTier(_ value: Double) -> Int {
        presets.min { abs(value - Double($0)) < abs(value - Double($1)) } ?? TipProducts.defaultAmount
    }
}
