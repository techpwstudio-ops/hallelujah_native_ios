import Foundation

/// One row of `GET /languages` (`getLanguagesApi`). Only the fields the
/// picker renders — see `LanguageOption`'s doc comment on why `id`/`image`/
/// `code`/`rank` aren't carried over.
struct LanguageOptionDTO: Decodable, Sendable {
    let name: String?
    let nameNative: String?
}

/// `LanguageNotifier.saveLanguages`'s request body: `{languages:
/// "a,b,c", primaryLanguage: "a"}` — comma-joined, already primary-first by
/// construction.
struct SaveLanguagesRequest: Encodable, Sendable {
    let languages: String
    let primaryLanguage: String?
}

/// The flat (not `{user: ...}`-wrapped) response shape `saveLanguages`
/// reads via `res.data['languages']`/`['primaryLanguage']`/`['status']` —
/// genuinely different from `CurrentUserResponse`, not reused by mistake.
struct SaveLanguagesResponse: Decodable, Sendable {
    let languages: String?
    let primaryLanguage: String?
    let status: String?
}
