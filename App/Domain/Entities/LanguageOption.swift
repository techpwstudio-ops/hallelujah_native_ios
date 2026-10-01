import Foundation

/// One row in the language picker. Ports `LanguageOption`
/// (`lib/providers/language_provider.dart`).
///
/// Dart also caches the full server row (id/image/code/rank) into Realm for
/// offline reuse; native has no equivalent local-DB layer yet and no other
/// call site needs those fields (`rank` only matters for ordering, and the
/// server already sends the list pre-sorted) — deliberately not carried
/// over, so this holds just what the picker itself renders.
struct LanguageOption: Sendable, Equatable, Identifiable {
    /// Canonical name — the value stored everywhere (the user's `languages`
    /// column, push topic names, content filters), so it is what gets
    /// selected and sent, never `nameNative`.
    let name: String

    /// The language in its own script, e.g. "हिन्दी". Nil for languages the
    /// server has no native spelling for.
    let nameNative: String?

    var id: String { name }

    /// What to render in the native slot, falling back to `name` so a
    /// language with no native spelling still shows something.
    var nativeLabel: String {
        let native = nameNative?.trimmingCharacters(in: .whitespaces)
        return (native?.isEmpty ?? true) ? name : native!
    }

    /// True when `nativeLabel` would just repeat `name` — English, Spanish
    /// and anything unmapped — so the UI can avoid printing the same word
    /// twice.
    var hasDistinctNative: Bool { nativeLabel != name }
}
