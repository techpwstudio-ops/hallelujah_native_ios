import Foundation

/// Typed access to the values `Config/*.xcconfig` publishes through `Info.plist`.
/// See D6 in `progress.md`: xcconfig -> Info.plist -> here, nothing inline in Swift.
struct AppConfiguration: Sendable {
    let environment: AppEnvironment
    let apiBaseURL: URL
    let proxyBaseURL: URL
    let socketBaseURL: URL
    let websiteHost: String
    let cdnHost: String
    /// The backend's `secure` request header. Empty until `Config/Secrets.xcconfig`
    /// (or CI) supplies `HALLELUJAH_API_SECRET` for a Production build — see
    /// Config/Secrets.xcconfig.template.
    let apiSecureHeader: String
    /// The unified OTP endpoints' body secrets (T20). Same empty-until-CI-supplies-it
    /// story as `apiSecureHeader` — see Config/Secrets.xcconfig.template.
    let otpSecret1: String
    let otpSecret2: String
    let logLevel: String
    let analyticsEnabled: Bool
    let crashReportingEnabled: Bool
    let featureFlags: FeatureFlags
    /// T23 — per-environment Firebase project identity, replacing a bundled
    /// `GoogleService-Info.plist` (this project has never had one; see
    /// `FirebaseBootstrap.configure()`, which builds a `FirebaseOptions`
    /// from these instead of relying on `FirebaseApp.configure()`'s default
    /// plist lookup) so the three environments can point at two genuinely
    /// different Firebase projects the same way every other cross-environment
    /// value here does.
    let firebase: FirebaseIdentity
    /// `AppConfig.serverClientId` (`lib/utils/app_config.dart` ->
    /// `DefaultFirebaseOptions.googleServerClientId`) — the Web OAuth client
    /// Google Sign-In scopes its returned ID token to, distinct from
    /// `firebase.googleIOSClientID`.
    let googleServerClientID: String

    struct FirebaseIdentity: Sendable {
        let apiKey: String
        let appID: String
        let projectID: String
        let storageBucket: String
        let gcmSenderID: String
        /// `GIDClientID` equivalent — the iOS app's own OAuth client,
        /// distinct from `googleServerClientID` above.
        let googleIOSClientID: String
    }

    static let current = AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])

    init(infoDictionary info: [String: Any]) {
        guard let environment = AppEnvironment(rawValue: info.requiredString("AppEnvironment")) else {
            preconditionFailure("Info.plist AppEnvironment does not match a known AppEnvironment case")
        }
        self.environment = environment

        apiBaseURL = Self.makeURL(
            scheme: info.requiredString("APIScheme"),
            host: info.requiredString("APIHost"),
            port: info.optionalString("APIPort"),
            path: info.requiredString("APIBasePath")
        )
        proxyBaseURL = Self.makeURL(
            scheme: info.requiredString("ProxyScheme"),
            host: info.requiredString("ProxyHost"),
            port: info.optionalString("ProxyPort"),
            path: info.requiredString("ProxyBasePath")
        )
        socketBaseURL = Self.makeURL(
            scheme: info.requiredString("SocketScheme"),
            host: info.requiredString("SocketHost"),
            port: info.optionalString("SocketPort"),
            path: ""
        )

        websiteHost = info.requiredString("WebsiteHost")
        cdnHost = info.requiredString("CDNHost")
        apiSecureHeader = info.optionalString("APISecureHeader") ?? ""
        otpSecret1 = info.optionalString("APIOTPSecret1") ?? ""
        otpSecret2 = info.optionalString("APIOTPSecret2") ?? ""
        logLevel = info.requiredString("LogLevel")
        analyticsEnabled = info.requiredFlag("AnalyticsEnabled")
        crashReportingEnabled = info.requiredFlag("CrashReportingEnabled")

        featureFlags = FeatureFlags(
            aiAssistantEnabled: info.requiredFlag("FeatureAIAssistantEnabled"),
            carPlayEnabled: info.requiredFlag("FeatureCarPlayEnabled"),
            adsEnabled: info.requiredFlag("FeatureAdsEnabled"),
            adsPreviewMode: info.requiredFlag("FeatureAdsPreviewMode"),
            downloadsEnabled: info.requiredFlag("FeatureDownloadsEnabled")
        )

        firebase = FirebaseIdentity(
            apiKey: info.requiredString("FirebaseAPIKey"),
            appID: info.requiredString("FirebaseAppID"),
            projectID: info.requiredString("FirebaseProjectID"),
            storageBucket: info.requiredString("FirebaseStorageBucket"),
            gcmSenderID: info.requiredString("FirebaseGCMSenderID"),
            googleIOSClientID: info.requiredString("GoogleIOSClientID")
        )
        googleServerClientID = info.requiredString("GoogleServerClientID")
    }

    /// `AppConfig.privacyPolicyUrl`/`termsAndConditionsUrl`
    /// (`lib/utils/app_config.dart`: `'$website/privacy'`/`'$website/terms'`)
    /// — used by `TermsAndPrivacyTextView` (T21). Dart's `website` getter
    /// splits dev vs. production; `websiteHost` doesn't (same host in every
    /// environment today, a pre-existing T05 simplification this task isn't
    /// re-opening), so both just build off it with a fixed `https` scheme.
    var privacyPolicyURL: URL { Self.makeURL(scheme: "https", host: websiteHost, port: nil, path: "/privacy") }
    var termsAndConditionsURL: URL { Self.makeURL(scheme: "https", host: websiteHost, port: nil, path: "/terms") }

    private static func makeURL(scheme: String, host: String, port: String?, path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port, let portNumber = Int(port) {
            components.port = portNumber
        }
        components.path = path

        guard let url = components.url else {
            preconditionFailure("Info.plist produced an invalid URL: \(scheme)://\(host):\(port ?? "-")\(path)")
        }
        return url
    }
}

private extension Dictionary where Key == String, Value == Any {
    func requiredString(_ key: String) -> String {
        guard let value = self[key] as? String, !value.isEmpty else {
            preconditionFailure("Missing required Info.plist key: \(key)")
        }
        return value
    }

    /// Empty strings are a valid "not set" for optional xcconfig values like ports.
    func optionalString(_ key: String) -> String? {
        guard let value = self[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    func requiredFlag(_ key: String) -> Bool {
        requiredString(key) == "YES"
    }
}
