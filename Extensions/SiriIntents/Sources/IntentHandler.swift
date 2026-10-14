import Intents

/// SiriKit Intents Extension entry point for "Hey Siri, play <song> in
/// Hallelujah" from CarPlay (or the phone). Runs in its own process, separate
/// from the main app -- it has no access to the app's authenticated session
/// (the token lives in the app's own Keychain item, not in a shared access
/// group). So this extension never calls the backend: it only captures
/// whatever text Siri parsed and hands off to the main app to do the real
/// search and play the result -- see `SiriPlayService` and the
/// `onContinueUserActivity` / `CarPlaySceneDelegate.scene(_:continue:)` hooks
/// in the app target.
class IntentHandler: INExtension, INPlayMediaIntentHandling {

    override func handler(for intent: INIntent) -> Any {
        return self
    }

    // MARK: - INPlayMediaIntentHandling

    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        guard let mediaName = intent.mediaSearch?.mediaName, !mediaName.isEmpty else {
            completion([INPlayMediaMediaItemResolutionResult.unsupported(forReason: .unsupportedMediaType)])
            return
        }

        // A placeholder item carrying only the raw spoken text -- there's no
        // catalog to resolve against here (see class comment above). Once
        // resolved, the system folds this back into `intent.mediaItems`,
        // which is what the main app reads on the other side of the
        // continuation to know what to search for.
        let item = INMediaItem(identifier: nil, title: mediaName, type: .song, artwork: nil)
        completion([INPlayMediaMediaItemResolutionResult.success(with: item)])
    }

    func confirm(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        // Playback must happen in the main app (CarPlay audio routes through
        // it, not this extension), so every confirmed request hands off
        // immediately rather than attempting anything here.
        completion(INPlayMediaIntentResponse(code: .continueInApp, userActivity: nil))
    }

    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        completion(INPlayMediaIntentResponse(code: .continueInApp, userActivity: nil))
    }
}
