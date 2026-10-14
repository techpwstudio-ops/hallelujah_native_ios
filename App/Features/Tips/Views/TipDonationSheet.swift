import SwiftUI

/// Ports `showTipToArtistSheet` (`lib/sheets/tip/showTipDonationSheet.dart`)
/// with Flutter metrics: 16 side / 20 top+bottom padding, its own 80x2 drag
/// handle, headlineSmall w700 title, white70 subtitle, "₹ amount" in
/// headlineMedium bold, black 12pt-radius "Say Thanks" field, Material
/// `ChoiceChip`s (10pt spacing, selected = #282828 with a check), optional
/// snapping slider and a white `FilledButton`.
///
/// Dumb UI: owns only the pending amount/note and forwards the result through
/// `onSend`; tapping Send dismisses immediately (as `NavigationService.back()`
/// does in Dart). Because this view draws Flutter's own drag handle, the host
/// sheet container must not add a second one.
struct TipDonationSheet: View {
    let artistName: String?
    let onSend: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss

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
            VStack(spacing: 0) {
                ParityDragHandler()
                Spacer().frame(height: 16)

                Text(title)
                    .font(AccountParity.font(24, .bold))
                    .foregroundStyle(AccountParity.white)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 8)

                Text("Show your appreciation for this music. Your support goes directly to the creator.")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white70)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 20)

                Text("₹ \(amount)")
                    .font(AccountParity.font(24, .bold))
                    .foregroundStyle(AccountParity.white)

                Spacer().frame(height: 16)

                noteField

                Spacer().frame(height: 16)

                presetChips

                Spacer().frame(height: 16)

                if showsSlider {
                    sliderSection
                    Spacer().frame(height: 10)
                }

                Spacer().frame(height: 20)

                ParityFilledButton(title: "Send ₹ \(amount)", fillWidth: true) {
                    guard amount >= minAmount else { return }
                    onSend(amount, note.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }

                Spacer().frame(height: 10)

                Text("Every contribution helps artists continue creating music.")
                    .font(AccountParity.bodySmall)
                    .foregroundStyle(Color.white.opacity(0.38))
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, Dimens.paddingLarge)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var noteField: some View {
        ZStack(alignment: .leading) {
            if note.isEmpty {
                Text("Say Thanks")
                    .font(AccountParity.bodyLarge)
                    .foregroundStyle(Color(red: 0.79, green: 0.77, blue: 0.82))
                    .allowsHitTesting(false)
            }
            TextField("", text: $note)
                .font(AccountParity.bodyLarge)
                .foregroundStyle(AccountParity.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AccountParity.black)
        )
    }

    /// `Wrap(spacing: 10)` of `ChoiceChip`s.
    private var presetChips: some View {
        FlowLayout(spacing: 10, lineSpacing: 0) {
            ForEach(presets, id: \.self) { preset in
                chip("₹ \(preset)", selected: amount == preset && !showsSlider) {
                    amount = preset
                    showsSlider = false
                }
            }
            chip("More", selected: showsSlider) {
                showsSlider = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AccountParity.white)
                }
                Text(label)
                    .font(AccountParity.font(14, .medium))
                    .tracking(0.1)
                    .foregroundStyle(selected ? AccountParity.white : Color(red: 0.79, green: 0.77, blue: 0.82))
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AccountParity.darkFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Color(red: 0x49 / 255, green: 0x45 / 255, blue: 0x4F / 255), lineWidth: 1)
            )
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sliderSection: some View {
        VStack(spacing: 0) {
            Slider(
                value: Binding(
                    get: { Double(amount) },
                    set: { amount = nearestTier($0) }
                ),
                in: Double(minAmount)...Double(maxAmount)
            )
            .tint(AccountParity.white)
            HStack {
                Text("₹ \(minAmount)")
                Spacer()
                Text("₹ \(maxAmount)")
            }
            .font(AccountParity.bodyMedium)
            .foregroundStyle(AccountParity.white)
        }
    }

    private func nearestTier(_ value: Double) -> Int {
        presets.min { abs(value - Double($0)) < abs(value - Double($1)) } ?? TipProducts.defaultAmount
    }
}

/// Minimal wrapping row layout (Flutter `Wrap`).
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
