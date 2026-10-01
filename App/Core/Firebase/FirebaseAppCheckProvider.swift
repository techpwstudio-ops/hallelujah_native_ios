import FirebaseAppCheck

/// `DioApi.instance.getAppCheckLimitedToken()` (`lib/services/DioService.dart`):
/// `FirebaseAppCheck.instance.getLimitedUseToken()` wrapped in a
/// swallow-every-error-to-`nil` `try`/`catch`. `AppCheck.appCheck()
/// .limitedUseToken()` is the iOS SDK's equivalent — `try?` reproduces the
/// same "never let this fail the sign-in" tolerance.
struct FirebaseAppCheckProvider: AppCheckProviding {
    func limitedUseToken() async -> String? {
        (try? await AppCheck.appCheck().limitedUseToken())?.token
    }
}
