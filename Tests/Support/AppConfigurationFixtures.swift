@testable import Hallelujah

/// A hand-built `AppConfiguration` matching Config/Environments/Staging.xcconfig,
/// for tests that need to target Staging regardless of which scheme built them.
extension AppConfiguration {
    static let staging = AppConfiguration(infoDictionary: [
        "AppEnvironment": "staging",
        "APIScheme": "https",
        "APIHost": "qa.api.hallelujah.today",
        "APIPort": "",
        "APIBasePath": "/api",
        "ProxyScheme": "https",
        "ProxyHost": "qa.proxy.hallelujah.today",
        "ProxyPort": "",
        "ProxyBasePath": "/api",
        "SocketScheme": "wss",
        "SocketHost": "qa.ws.hallelujah.today",
        "SocketPort": "",
        "WebsiteHost": "hallelujah.today",
        "CDNHost": "d124ttxt2as03p.cloudfront.net",
        "APISecureHeader": "s3",
        "LogLevel": "debug",
        "AnalyticsEnabled": "YES",
        "CrashReportingEnabled": "YES",
        "FeatureAIAssistantEnabled": "YES",
        "FeatureCarPlayEnabled": "YES",
        "FeatureAdsEnabled": "YES",
        "FeatureAdsPreviewMode": "YES",
        "FeatureDownloadsEnabled": "YES",
        "FeatureTipButtonEnabled": "YES",
    ])
}
