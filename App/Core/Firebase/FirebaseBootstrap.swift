import FirebaseAppCheck
import FirebaseCore
import FirebaseCrashlytics
import GoogleSignIn

/// Ports the Firebase-related slice of `main()` (`lib/main.dart`) that has to
/// run before anything else touches Firebase. Two things Dart's `main()`
/// does around this that aren't here:
/// - `FirebaseMessaging.onBackgroundMessage(...)` — FCM's own bootstrap,
///   deferred to T18 (push-driven deep links) per T15's roadmap scope.
/// - `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError`
///   — Flutter-specific: it hooks Flutter's *caught* widget-build error
///   channel. Crashlytics' iOS SDK installs its own signal/exception handler
///   during `configure()`/collection-enable and captures native crashes on
///   its own; there's no equivalent "framework caught this non-fatal error"
///   channel to hook here. `FirebaseCrashReporter.recordError(_:)` is this
///   app's equivalent surface for Swift call sites that catch an `Error`
///   they want reported without crashing.
enum FirebaseBootstrap {
    /// Not `@MainActor`-isolated at the type level — Firebase's ObjC-bridged
    /// APIs here carry no Swift actor annotations of their own, so nothing
    /// requires it structurally. Its only call site (`AppComposition.
    /// installRuntime()`, from `GHallelujahApp.init()`) already runs on the
    /// main actor, which is what Firebase actually wants at runtime.
    static func configure() {
        // Must run before `FirebaseApp.configure()` — the App Check provider
        // factory only takes effect if it's set first.
        AppCheck.setAppCheckProviderFactory(GHallelujahAppCheckProviderFactory())

        // T23 — no `GoogleService-Info.plist` has ever been bundled with this
        // target (confirmed by its absence when T23 needed Google Sign-In's
        // own client IDs), so `FirebaseApp.configure()`'s default plist
        // lookup would silently do nothing on every environment, not just
        // this one; built explicitly from `AppConfiguration.firebase`
        // instead, which already carries every environment's project
        // identity through the same xcconfig -> Info.plist pipeline (D6)
        // everything else here uses.
        let firebase = AppConfiguration.current.firebase
        let options = FirebaseOptions(googleAppID: firebase.appID, gcmSenderID: firebase.gcmSenderID)
        options.apiKey = firebase.apiKey
        options.projectID = firebase.projectID
        options.storageBucket = firebase.storageBucket
        options.clientID = firebase.googleIOSClientID
        options.bundleID = Bundle.main.bundleIdentifier ?? ""
        FirebaseApp.configure(options: options)

        // `buildHeaders()`'s `app-check-token` (`DioService.dart`) — every
        // `HTTPClient` reads the cached token through the shared provider.
        RequestHeaderProvider.shared.installAppCheckSource(FirebaseAppCheckTokenSource())

        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(
            AppConfiguration.current.crashReportingEnabled
        )

        // T23 — `GoogleSignIn.instance.initialize(serverClientId:)`
        // (`lib/blocs/auth/bloc.dart`'s `googleSignIn`). Configuring once
        // here, rather than per sign-in attempt, matches `GIDSignIn`'s own
        // documented usage (`sharedInstance.configuration` is read at the
        // start of every `signIn` call).
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: firebase.googleIOSClientID,
            serverClientID: AppConfiguration.current.googleServerClientID
        )
    }
}
