import Foundation
import Observation

enum LanguageSaveState: Equatable {
    case idle
    case loading
    case success
    case error(message: String)
}

/// Ports `LanguageNotifier`/`LanguageState`
/// (`lib/providers/language_provider.dart`) — the state behind both
/// `ContentLanguageUi` (signup, T25, this task) and `ContentLanguagePage`
/// (Settings, T70, not built yet). Built as a shared, standalone view model
/// rather than `AccountSetupView`-private: `toggleLanguageWithLimit`'s own
/// Dart doc comment says both the signup and Settings grids go through the
/// same toggle logic "so the cap is worded once", and T70 already claims
/// `settings_screen.dart` parity in progress.md.
///
/// `setPrimaryLanguage`/`PrimaryLanguagePicker` are deliberately not ported:
/// grepping every call site found `PrimaryLanguagePicker` itself is dead
/// code in the Flutter app (defined, never referenced) — an older
/// single-select design already superseded by the "order of picking IS the
/// answer" rule this type implements. Nothing to port because Dart itself
/// doesn't use it either.
@MainActor
@Observable
final class LanguageViewModel {
    /// `LanguageNotifier.maxSelectableLanguages`. A cap exists because the
    /// selection seeds the home feed: every language adds another set of
    /// rails to fetch and merge, and past a handful "preference" becomes
    /// "everything", which is the same as no preference at all.
    static let maxSelectableLanguages = 6

    private(set) var languageOptions: [LanguageOption] = []
    private(set) var selectedLanguages: [String] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var saveState: LanguageSaveState = .idle

    private let authRepository: any AuthRepository
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        authRepository = container.resolve()
        currentUserStore = container.resolve()
    }

    /// The language the user is reached in: push topics, the main feed.
    /// Derived, not stored, so it cannot disagree with `selectedLanguages`.
    var primaryLanguage: String? { selectedLanguages.first }
    var secondaryLanguages: [String] { Array(selectedLanguages.dropFirst()) }
    var hasSelection: Bool { !selectedLanguages.isEmpty }
    var isSelectionFull: Bool { selectedLanguages.count >= Self.maxSelectableLanguages }

    func isPrimary(_ name: String) -> Bool { primaryLanguage == name }
    func isSelected(_ name: String) -> Bool { selectedLanguages.contains(name) }
    /// Whether tapping `name` would do anything. Already-selected cards stay
    /// tappable at the cap — deselecting is how you get back under it.
    func canToggle(_ name: String) -> Bool { isSelected(name) || !isSelectionFull }
    func optionFor(_ name: String) -> LanguageOption? { languageOptions.first { $0.name == name } }

    /// Fetches the list, then seeds the selection from the cached user's
    /// `languages`/`primaryLanguage` — comma-joined, order preserved,
    /// deduplicated, with an explicitly stored primary moved to the front.
    /// A fresh signup has neither set, so the grid starts EMPTY: the old
    /// screen pre-ticked English, which is how most accounts ended up on
    /// English as a UI artefact rather than a preference.
    func initialize() async {
        await fetchLanguages()

        let user = await currentUserStore.user
        let saved = (user?.languages ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var ordered: [String] = []
        for name in saved where !ordered.contains(name) {
            ordered.append(name)
        }

        if let storedPrimary = user?.primaryLanguage?.trimmingCharacters(in: .whitespaces), !storedPrimary.isEmpty {
            ordered.removeAll { $0 == storedPrimary }
            ordered.insert(storedPrimary, at: 0)
        }

        selectedLanguages = ordered
    }

    func fetchLanguages() async {
        isLoading = true
        errorMessage = nil
        do {
            languageOptions = try await authRepository.fetchLanguages()
        } catch {
            logger.warning("fetch languages failed: \(error)")
            errorMessage = "Network error"
        }
        isLoading = false
    }

    /// Select or deselect `name`. Selecting appends, so the FIRST language
    /// tapped stays primary however many are added after it; deselecting
    /// the primary promotes whatever was picked next.
    ///
    /// Returns false when refused because the selection is already at
    /// `maxSelectableLanguages` — the caller (not this method) surfaces the
    /// toast, mirroring `toggleLanguageWithLimit`'s split.
    @discardableResult
    func toggleLanguage(_ name: String) -> Bool {
        if let index = selectedLanguages.firstIndex(of: name) {
            selectedLanguages.remove(at: index)
            return true
        }
        guard !isSelectionFull else { return false }
        selectedLanguages.append(name)
        return true
    }

    /// Backs the Reset action (`_ResetLanguagesAction`, `account_setup_page.dart`).
    func reset() {
        selectedLanguages = []
    }

    /// `LanguageNotifier.saveLanguages` — client-side checks first (both
    /// toast-only in Dart, so surfaced here as `saveState.error` for the
    /// caller to show rather than thrown), then the network call. Returns
    /// whether the caller should proceed, matching Dart's `bool` return.
    @discardableResult
    func saveLanguages() async -> Bool {
        guard hasSelection else {
            saveState = .error(message: "Please select at least 1 language")
            return false
        }
        guard selectedLanguages.count <= Self.maxSelectableLanguages else {
            saveState = .error(message: "You can select up to \(Self.maxSelectableLanguages) languages")
            return false
        }

        saveState = .loading
        do {
            try await authRepository.saveLanguages(selectedLanguages, primaryLanguage: primaryLanguage)
            saveState = .success
            return true
        } catch let error as AuthOTPError {
            saveState = .error(message: error.message)
            return false
        } catch {
            logger.warning("save languages failed: \(error)")
            saveState = .error(message: "Network error")
            return false
        }
    }
}
