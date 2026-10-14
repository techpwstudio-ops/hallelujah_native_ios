import SwiftUI

/// States the primary/secondary rule and the selection cap up front.
///
/// Neither is discoverable by doing: you would have to pick two languages
/// and notice the badges differ, or pick a seventh and find it refused.
/// Ports `RuleBanner` (`lib/widgets/authentication/read_language.dart`).
struct RuleBannerView: View {
    var body: some View {
        HStack(alignment: .top, spacing: Dimens.spacing8) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(.white)

            (
                Text("1st pick becomes ")
                    + Text("PRIMARY").fontWeight(.bold).foregroundColor(.white)
                    + Text(". Additional choices become ")
                    + Text("SECONDARY").fontWeight(.bold).foregroundColor(.white)
                    + Text(". Pick up to ")
                    + Text("\(LanguageViewModel.maxSelectableLanguages) languages").fontWeight(.bold).foregroundColor(.white)
                    + Text(".")
            )
            .typography(Typography.bodySmall)
            .foregroundStyle(AuthColors.secondaryText)
            .lineSpacing(6)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AuthColors.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(AuthColors.white12, lineWidth: 1)
                }
        }
    }
}

/// One language card in the picker grid. Ports `LanguageSelectionItem`
/// (`lib/widgets/authentication/language_selection_item.dart`) — shown
/// twice on purpose (English name identifies it, the native spelling is
/// what a speaker actually recognises) unless `option.hasDistinctNative` is
/// false.
///
/// `isDisabled` only dims the card; `onTap` still fires (an unselected card
/// at the cap explains the refusal on tap rather than doing nothing).
struct LanguageSelectionItemView: View {
    let option: LanguageOption
    let isSelected: Bool
    let isPrimary: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .typography(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : AuthColors.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        roleBadge
                    } else {
                        emptyIndicator
                    }
                }
                Text(option.nativeLabel)
                    .typography(Typography.titleLarge)
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? .white : AuthColors.secondaryText)
                    .lineLimit(1)
            }
            .padding(Dimens.paddingLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(isSelected ? AuthColors.accentFill : AuthColors.fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(isSelected ? AuthColors.accentBorder : .clear, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1.7, contentMode: .fit)
        .opacity(isDisabled ? 0.4 : 1)
    }

    private var roleBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 12))
            Text(isPrimary ? "PRIMARY" : "SECONDARY")
                .typography(Typography.labelSmall)
                .fontWeight(.bold)
                .tracking(0.4)
        }
        .foregroundStyle(isPrimary ? .black : AuthColors.secondaryText)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(isPrimary ? Color.white : AuthColors.white12)
        }
    }

    private var emptyIndicator: some View {
        Circle()
            .strokeBorder(AuthColors.white24, lineWidth: 1.5)
            .frame(width: 16, height: 16)
    }
}

/// Two-column grid of language cards, in the order the server sent them.
/// Ports `_LanguageGrid` (`read_language.dart`).
struct LanguageGridView: View {
    let languageOptions: [LanguageOption]
    let isSelected: (String) -> Bool
    let isPrimary: (String) -> Bool
    let canToggle: (String) -> Bool
    let onTap: (String) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(languageOptions) { option in
                LanguageSelectionItemView(
                    option: option,
                    isSelected: isSelected(option.name),
                    isPrimary: isPrimary(option.name),
                    isDisabled: !canToggle(option.name),
                    onTap: { onTap(option.name) }
                )
            }
        }
    }
}

/// Pinned footer: what is selected, plus the primary action. Ports
/// `LanguageSelectionSummary`/`_SummaryPanel`/`_ContinueButton`
/// (`read_language.dart`) as one view — Dart splits `_SummaryPanel` out
/// only so `ConsumerWidget` can rebuild it independently, which
/// `@Observable` makes unnecessary here.
///
/// Reusable across the signup step (T25, this task) and the Settings screen
/// (T70's `ContentLanguagePage`, not built yet) — `continueLabel` is
/// "Continue" for signup, "Save" for Settings, matching Dart's own single
/// widget serving both hosts.
struct LanguageSelectionSummaryView: View {
    let viewModel: LanguageViewModel
    var continueLabel: String = "Continue"
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasSelection {
                summaryPanel
            }
            continueButton
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Selected Preferences")
                    .typography(Typography.bodySmall)
                    .foregroundStyle(AuthColors.tertiaryText)
                Spacer()
                Text(countLabel)
                    .typography(Typography.labelSmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(AuthColors.accentSurface) }
            }

            if let primary = viewModel.primaryLanguage {
                Spacer().frame(height: Spacing.sm)
                summaryRow(badge: "PRIMARY", isPrimary: true, value: label(for: primary), trailing: "Main Feed")
            }
            if !viewModel.secondaryLanguages.isEmpty {
                Spacer().frame(height: 6)
                summaryRow(badge: "SECONDARY", isPrimary: false, value: viewModel.secondaryLanguages.joined(separator: ", "), trailing: nil)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AuthColors.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(AuthColors.white12, lineWidth: 1)
                }
        }
    }

    private var countLabel: String {
        let count = viewModel.selectedLanguages.count
        let noun = count == 1 ? "language" : "languages"
        return "\(count) of \(LanguageViewModel.maxSelectableLanguages) \(noun) selected"
    }

    /// "Hindi (हिन्दी)" — just "English" when the native spelling would only
    /// repeat the name.
    private func label(for name: String) -> String {
        guard let option = viewModel.optionFor(name), option.hasDistinctNative else { return name }
        return "\(name) (\(option.nativeLabel))"
    }

    private func summaryRow(badge: String, isPrimary: Bool, value: String, trailing: String?) -> some View {
        HStack(spacing: 0) {
            Text(badge)
                .typography(Typography.labelSmall)
                .fontWeight(.bold)
                .tracking(0.4)
                .foregroundStyle(isPrimary ? .black : AuthColors.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isPrimary ? Color.white : AuthColors.darkFill)
                }
            Spacer().frame(width: Dimens.spacing8)
            Text(value)
                .typography(Typography.bodySmall)
                .fontWeight(isPrimary ? .semibold : .regular)
                .foregroundStyle(isPrimary ? .white : AuthColors.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing)
                    .typography(Typography.labelSmall)
                    .foregroundStyle(AuthColors.tertiaryText)
            }
        }
    }

    /// `Loader.instance.show()` blocks the whole app while Dart's version
    /// saves; there's no app-wide loader here, so disabling the button
    /// itself during `saveState == .loading` is the local equivalent.
    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: Spacing.sm) {
                Text(continueLabel)
                    .typography(Typography.titleSmall)
                    .fontWeight(.semibold)
                if viewModel.saveState == .loading {
                    MaterialSpinner(color: .black, size: 20, lineWidth: 2.5)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: Radius.full, style: .continuous)
                    .fill(AuthColors.accentActionGradient)
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.hasSelection || viewModel.saveState == .loading)
        .opacity(viewModel.hasSelection ? 1 : 0.4)
    }
}
