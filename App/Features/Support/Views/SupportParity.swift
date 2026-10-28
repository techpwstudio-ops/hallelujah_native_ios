import SwiftUI

/// `CustomButton` (`lib/widgets/widgets.dart`): full width, 14pt vertical
/// padding, 12pt radius, `titleSmall` w600. Primary = white / greyDark when
/// disabled; secondary = clear with white24 border and white70 label.
struct SupportCustomButton: View {
    let text: LocalizedStringKey
    var enabled: Bool = true
    var isSecondary: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    /// `ColorTheme.greyDark` = `Colors.grey.shade800` (0xFF424242).
    private static let greyDark = Color(red: 0x42 / 255, green: 0x42 / 255, blue: 0x42 / 255)

    private var background: Color {
        if isSecondary { return Color.clear }
        return enabled ? AccountParity.white : Self.greyDark
    }

    private var foreground: Color {
        if isSecondary { return AccountParity.white70 }
        return enabled ? AccountParity.black : Color.white.opacity(0.38)
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    Text(text)
                        .font(AccountParity.font(14, .semibold))
                        .foregroundStyle(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Dimens.spacing16 - 2)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous).fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(isSecondary ? AccountParity.white24 : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
    }
}

/// Sticky bottom bar of the Feedback / Delete Account pages: black, 1pt
/// white-8% top rule, padding (16, 12, 16, 20), 10pt between buttons.
struct SupportBottomBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(.leading, 16)
        .padding(.top, 12)
        .padding(.trailing, 16)
        .padding(.bottom, 20)
        // Native-only tablet/Mac adaptation (no Flutter counterpart): buttons
        // line up with the page's readable column; the bar itself stays full width.
        .readableContentWidth()
        .frame(maxWidth: .infinity)
        .background(AccountParity.black)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }
}

/// `dropDownInput` (`lib/widgets/widgets.dart`): "<hint> *" label (titleSmall),
/// 52pt field with white10 fill + border, 12pt radius, "Select <hint>" placeholder.
struct SupportDropdown: View {
    struct Item: Identifiable, Equatable {
        let label: String
        let value: String
        var id: String { value }
    }

    let hint: String
    let items: [Item]
    let selectedValue: String?
    var isDisabled: Bool = false
    let onSelect: (Item) -> Void

    private var selectedLabel: String? {
        items.first(where: { $0.value == selectedValue })?.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(verbatim: hint).font(AccountParity.titleSmall).foregroundStyle(AccountParity.white)
                + Text(" *").font(AccountParity.titleSmall).foregroundStyle(AccountParity.red))
                .padding(.bottom, Dimens.spacing6)

            Menu {
                ForEach(items) { item in
                    Button(item.label) { onSelect(item) }
                }
            } label: {
                HStack {
                    Text(verbatim: selectedLabel ?? String(localized: "Select \(hint)"))
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(selectedLabel == nil ? Color(red: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255) : AccountParity.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.74, green: 0.74, blue: 0.74))
                }
                .padding(.horizontal, Dimens.paddingMedium)
                .frame(height: Dimens.buttonHeight)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous).fill(AccountParity.white10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(AccountParity.white10, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
    }
}
