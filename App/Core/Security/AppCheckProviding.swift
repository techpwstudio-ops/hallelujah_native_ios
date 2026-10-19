/// `DioApi.instance.getAppCheckLimitedToken()` (`lib/services/DioService.dart`)
/// — a Firebase App Check limited-use token attached to the unified OTP
/// endpoints' body (`AuthOtpService.send`/`.verify`,
/// `lib/features/authentication/data/auth_otp_service.dart`).
protocol AppCheckProviding: Sendable {
    func limitedUseToken() async -> String?
}

/// A stand-in for previews/tests, where activating real App Check has no
/// value. Not used at runtime — `FirebaseAppCheckProvider`
/// (`App/Core/Firebase/`) is the real implementation `AppComposition`
/// registers, since T15 already activated the provider factory
/// (`HallelujahAppCheckProviderFactory`, `FirebaseBootstrap.configure()`)
/// it depends on.
struct UnavailableAppCheckProvider: AppCheckProviding {
    func limitedUseToken() async -> String? { nil }
}
