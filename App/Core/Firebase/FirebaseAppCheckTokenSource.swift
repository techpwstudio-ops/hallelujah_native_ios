import FirebaseAppCheck

/// `FirebaseAppCheck.instance.getToken()` (`DioApi._getAppCheckToken`) — the
/// regular (cacheable) App Check token attached to every API request as the
/// `app-check-token` header, as opposed to the limited-use token
/// `FirebaseAppCheckProvider` produces for the auth endpoints' bodies.
/// Errors collapse to `nil`, same as Dart's empty `catch (_) {}`.
struct FirebaseAppCheckTokenSource: AppCheckTokenSource {
    func currentToken() async -> String? {
        (try? await AppCheck.appCheck().token(forcingRefresh: false))?.token
    }
}
