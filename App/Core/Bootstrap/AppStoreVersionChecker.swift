import Foundation

struct AppStoreVersionInfo: Sendable, Equatable {
    let version: String
    let trackViewURL: URL
}

protocol AppStoreVersionChecking: Sendable {
    /// `nil` on any failure — network error, decode failure, no result, or
    /// no newer version — matching the fail-open behavior a version-check
    /// gate needs: a broken lookup should never block or nag the user.
    func checkForUpdate() async -> AppStoreVersionInfo?
}

/// Native replacement for the `upgrader` package's force-upgrade gate
/// (`UpgradeAlert(child: FlashScreen())` in `lib/routes/app_router.dart` —
/// `UpgradeAlert` wraps, not gates, the flash route: dismissible, never
/// blocking). `upgrader`'s iOS path queries the same iTunes Lookup API
/// this does; there's
/// no single Dart source file to point at since the logic lives inside the
/// package, but the endpoint and version comparison are the standard iOS
/// App Store version check.
struct ITunesAppStoreVersionChecker: AppStoreVersionChecking {
    private let bundleID: String
    private let currentVersion: String
    private let session: URLSession

    init(
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        session: URLSession = .shared
    ) {
        self.bundleID = bundleID
        self.currentVersion = currentVersion
        self.session = session
    }

    func checkForUpdate() async -> AppStoreVersionInfo? {
        guard !bundleID.isEmpty,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)")
        else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let lookup = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let result = lookup.results.first,
                  let storeURL = URL(string: result.trackViewUrl),
                  result.version.compare(currentVersion, options: .numeric) == .orderedDescending
            else { return nil }
            return AppStoreVersionInfo(version: result.version, trackViewURL: storeURL)
        } catch {
            return nil
        }
    }

    private struct LookupResponse: Decodable {
        let results: [Result]

        struct Result: Decodable {
            let version: String
            let trackViewUrl: String
        }
    }
}
