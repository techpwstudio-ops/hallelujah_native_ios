import SwiftUI

/// `BookPageLanguageSheet` (`lib/sheets/book/book_page_language_sheet.dart`):
/// drag handle, a "Search language" field (#1D1D1D fill, 8pt radius, 20pt
/// search glyph, clear button once typing) and one titleMedium w500 row per
/// language with the offline-download control trailing. Tapping the row
/// switches the reader to that language. Empty states copy Flutter: "No
/// languages available" / "No languages downloaded for offline reading yet"
/// (offline) / `No language matches "<query>"`.
struct LanguagePickerSheet: View {
    let languages: [BibleLanguage]
    let currentLanguage: String
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var isOnline: Bool
    @State private var service: BibleOfflineDownloadService = DependencyContainer.current.resolve()
    @FocusState private var isSearchFocused: Bool

    init(languages: [BibleLanguage], currentLanguage: String, onSelect: @escaping (String) -> Void) {
        self.languages = languages
        self.currentLanguage = currentLanguage
        self.onSelect = onSelect
        let reachability: any ReachabilityMonitoring = DependencyContainer.current.resolve()
        _isOnline = State(initialValue: reachability.isOnline)
    }

    /// Offline, a language can't be fetched on demand, so only ones already
    /// fully downloaded are offered.
    private var available: [BibleLanguage] {
        isOnline ? languages : languages.filter { service.isLanguageDownloaded($0.language) }
    }

    private var filtered: [BibleLanguage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return available }
        return available.filter { $0.language.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ReadDragHandle()

            if available.isEmpty {
                ReadEmptyText(
                    text: isOnline
                        ? "No languages available"
                        : "No languages downloaded for offline reading yet"
                )
                .frame(maxHeight: .infinity)
            } else {
                searchField
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

                if filtered.isEmpty {
                    ReadEmptyText(text: "No language matches \"\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { language in
                                row(for: language)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(ReadPalette.white60)
                .frame(width: 48)
            TextField(
                "",
                text: $searchText,
                prompt: Text("Search language").foregroundColor(ReadPalette.hint)
            )
            .typography(Typography.bodyLarge)
            .foregroundStyle(ReadPalette.white)
            .tint(ReadPalette.white)
            .submitLabel(.search)
            .focused($isSearchFocused)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(ReadPalette.white60)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(ReadPalette.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isSearchFocused ? ReadPalette.white24 : Color.clear, lineWidth: 1)
        )
    }

    private func row(for language: BibleLanguage) -> some View {
        HStack(spacing: 16) {
            Text(language.language)
                .readText(Typography.titleMedium, weight: .medium)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if !language.language.isEmpty {
                BibleOfflineDownloadButton(language: language.language)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(language.language)
        }
    }
}
