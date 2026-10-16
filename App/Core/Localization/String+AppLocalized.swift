import Foundation

extension String {
    /// Shadows Foundation's `String(localized:)` for the whole module (same
    /// signature, so every existing call site picks this one) to resolve in the
    /// in-app language (`AppLocalization`) rather than the language the process
    /// launched in — see `AppLocalization` for why the stock one goes stale after
    /// a runtime language switch.
    ///
    /// Reading `AppLanguageSignal` makes a SwiftUI `body` that calls this
    /// re-render when the language changes (it is a no-op outside observation
    /// tracking).
    init(
        localized keyAndValue: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle? = nil,
        locale: Locale = .current,
        comment: StaticString? = nil
    ) {
        _ = AppLanguageSignal.shared.generation
        let bundleDescription: LocalizedStringResource.BundleDescription = bundle.map { .atURL($0.bundleURL) } ?? .main
        self = String(
            localized: LocalizedStringResource(
                keyAndValue,
                table: table,
                locale: AppLocalization.locale,
                bundle: bundleDescription,
                comment: comment
            )
        )
    }
}

extension AttributedString {
    /// `AttributedString(localized:)` has the same launch-language problem and
    /// ignores its `locale:`. Resolves the (markdown) key through the
    /// `String(localized:)` replacement above, then parses it. Use for strings
    /// carrying `**bold**`; the key and catalog entry are the same as before.
    init(appLocalized keyAndValue: String.LocalizationValue) {
        let resolved = String(localized: keyAndValue)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        self = (try? AttributedString(markdown: resolved, options: options)) ?? AttributedString(resolved)
    }
}
