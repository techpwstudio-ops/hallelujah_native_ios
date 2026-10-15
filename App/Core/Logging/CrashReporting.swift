import FirebaseCrashlytics
import Foundation

/// Keeps any crash-reporting vendor SDK out of app code — call sites depend
/// on this protocol, never on a vendor type directly.
protocol CrashReporting: Sendable {
    func recordError(_ error: any Error)
    func log(_ message: String)
}

struct NoOpCrashReporter: CrashReporting {
    func recordError(_ error: any Error) {}
    func log(_ message: String) {}
}

/// Q5 (progress.md Open questions), answered 2026-09-16: Crashlytics is one
/// of the five Firebase products that carry over. Registered by
/// `AppComposition` once `FirebaseBootstrap.configure()` has run — Crashlytics
/// (like every Firebase product) is unusable before `FirebaseApp.configure()`.
struct FirebaseCrashReporter: CrashReporting {
    func recordError(_ error: any Error) {
        Crashlytics.crashlytics().record(error: error)
        reportToServer(error)
    }

    /// `AnalyticSession._reportToServer` (`analytics_session.dart`): outside
    /// production every tracked error is also posted to `/client-log/error`
    /// as `{message, stackTrace}` so QA can read them server-side. Fire and
    /// forget, and silent — failing to log an error must never raise one.
    private func reportToServer(_ error: any Error) {
        guard AppConfiguration.current.environment != .production,
              let client = DependencyContainer.current.resolveIfRegistered(HTTPClient.self) else { return }
        let payload = [
            "message": "[native] \(error)",
            "stackTrace": Thread.callStackSymbols.joined(separator: "\n"),
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        Task.detached {
            _ = try? await client.send(.clientErrorLog, body: body, silent: true)
        }
    }

    /// `FirebaseCrashlytics.instance.log(...)` in Dart
    /// (`lib/main.dart`'s `FlutterError.onError` wiring uses
    /// `recordFlutterError` for actual errors; `log` is Crashlytics' own
    /// breadcrumb API, surfaced here 1:1) — breadcrumbs attached to the
    /// *next* recorded crash/error, not sent on their own.
    func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }
}
