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
    /// The tip amounts this store sells (`offeringsProvider`) — every choice
    /// is one of them, because a store can only charge a pre-configured product.
    let offerings: [Offering]
    let onSend: (Offering, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selected: Offering
    @State private var showsAll = false
    @State private var note = ""

    /// Rows of amount chips shown before the rest hides behind "More".
    private static let collapsedRows = 2

    init(artistName: String?, offerings: [Offering], onSend: @escaping (Offering, String) -> Void) {
        self.artistName = artistName
        self.offerings = offerings
        self.onSend = onSend
        // The host never presents the sheet for an empty list.
        _selected = State(initialValue: Offering.initialSelection(in: offerings)
            ?? Offering(id: "", amount: 0, currency: "INR", productID: ""))
    }

    private var title: String {
        let trimmed = artistName?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? String(localized: "Support the Artist") : String(localized: "Support \(trimmed)")
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

                Text("Show your appreciation for this music. The creator receives a share of every tip.")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white70)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 20)

                Text(verbatim: selected.priceLabel)
                    .font(AccountParity.font(24, .bold))
                    .foregroundStyle(AccountParity.white)
                if let label = selected.label {
                    Text(verbatim: label)
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(AccountParity.white70)
                }

                Spacer().frame(height: 16)

                noteField

                Spacer().frame(height: 16)

                presetChips

                Spacer().frame(height: 16)

                Spacer().frame(height: 20)

                ParityFilledButton(title: "Send \(selected.priceLabel)", fillWidth: true) {
                    guard !selected.id.isEmpty else { return }
                    onSend(selected, note.trimmingCharacters(in: .whitespacesAndNewlines))
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

    /// `ClampedWrap`: two rows of chips; row 2 ends with "More" when there are more.
    private var presetChips: some View {
        ClampedWrapLayout(maxRows: Self.collapsedRows, expanded: showsAll, hasMore: true, spacing: 8, runSpacing: 8) {
            ForEach(offerings) { offering in
                chip(offering.priceLabel, selected: selected.id == offering.id) {
                    selected = offering
                }
            }
            chip(String(localized: "More"), selected: false) {
                showsAll = true
            }
        }
        .clipped()
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
}
