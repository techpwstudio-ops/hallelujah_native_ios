import Foundation

/// `OurSession.changeReadLanguage` (`lib/utils/session.dart`): after the reader
/// picks a Bible language, the account's `bibleLanguage` is updated in the
/// cached user and `POST /user/save/bible-language {language}` is fired and
/// forgotten (the verse-of-day push topic follows the server-side value).
struct ReadLanguageSaver {
    private struct Body: Encodable {
        let language: String
    }

    private let client: HTTPClient
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        client = container.resolve()
        currentUserStore = container.resolve()
    }

    func save(language: String) async {
        if var user = await currentUserStore.user {
            user.bibleLanguage = language
            await currentUserStore.setUser(user)
        }
        // `changeReadLanguage` -> `subscribeVerseOfDay()`: the daily-verse
        // push topic is per Bible language.
        await FCMTopicManager.shared.bibleLanguageDidChange()
        do {
            let body = try JSONEncoder().encode(Body(language: language))
            let response = try await client.send(.saveBibleLanguage, body: body)
            if response.statusCode >= 400 {
                logger.warning("save bible language failed: \(response.statusCode)")
            }
        } catch {
            logger.warning("save bible language failed: \(error)")
        }
    }
}
