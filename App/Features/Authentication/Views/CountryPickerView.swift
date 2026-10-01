import SwiftUI

/// Ported from `showCountryPicker` (`country_picker` pub package, called by
/// `phone_auth_screen.dart`'s `_showCountryPicker`): a searchable, scrollable
/// list of every `Country`, with India pinned to the top via
/// `favorite: const ['IN']`.
///
/// Presented as an `.appSheet(...)` rather than hand-building Dart's own
/// sheet chrome (`bottomSheetBgColor`, 18pt top corners) — sheets are
/// explicitly out of D10's pixel-parity scope (`AppSheet.swift`'s own doc
/// comment), so the standard glass sheet container applies here same as
/// anywhere else in the app.
///
/// Deliberately reproduces the package's un-deduplicated favorites section
/// (see `Country.favorites`'s doc comment) rather than "fixing" it — India
/// renders once pinned at the top, and again at its natural alphabetical
/// position in the full list below.
struct CountryPickerView: View {
    let onSelect: (Country) -> Void

    @State private var searchText = ""
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var filteredCountries: [Country] {
        guard !searchText.isEmpty else { return Country.all }
        return Country.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.dialCode.contains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(Spacing.md)

            List {
                if searchText.isEmpty {
                    Section {
                        ForEach(Country.favorites) { country in
                            row(for: country)
                        }
                    }
                }
                Section {
                    ForEach(filteredCountries) { country in
                        row(for: country)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            theme.icon(.search)
                .foregroundStyle(theme.color(.textTertiary))
            TextField("Search country", text: $searchText)
                .typography(Typography.bodyMedium)
                .foregroundStyle(theme.color(.textPrimary))
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: Spacing.inputHeight)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.color(.surfaceInput))
        }
    }

    private func row(for country: Country) -> some View {
        Button {
            onSelect(country)
            dismiss()
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(country.flagEmoji)
                Text(country.name)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textPrimary))
                Spacer()
                Text(country.dialCodeDisplay)
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(theme.color(.textSecondary))
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }
}
