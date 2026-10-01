import FirebaseAppCheck

/// Matches `main.dart`'s `FirebaseAppCheck.instance.activate(providerApple:)`
/// exactly: `AppleDeviceCheckProvider` (`DeviceCheckProvider` in the iOS SDK)
/// for release, `AppleDebugProvider` (`AppCheckDebugProvider`) for debug —
/// deliberately not the newer `AppAttestProvider`, per Q5's resolution
/// (progress.md Open questions): the native port carries over Dart's actual
/// choice rather than upgrading to a provider Dart never opted into.
final class GHallelujahAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        #if DEBUG
        AppCheckDebugProvider(app: app)
        #else
        DeviceCheckProvider(app: app)
        #endif
    }
}
