import Foundation

/// Ports `CountryService` (`lib/services/country_service.dart`): resolves the
/// device's country, offline first (timezone + locale region), falling back to
/// `GET /geo/country` only when the offline answer is not India/Sri Lanka, and
/// caches the verdict for seven days (invalidated by a timezone-offset change).
///
/// Nothing in the Flutter UI reads the result today beyond `main.dart` warming
/// it, so this is a faithful service port with no screen wiring.
actor CountryService {
    static let indiaOffsetMinutes = 5 * 60 + 30
    static let mobileOtpCountries: Set<String> = ["IN"]

    private enum Key {
        static let country = "geo_country_code"
        static let offset = "geo_country_offset_minutes"
        static let mobileOtp = "geo_mobile_otp_enabled"
        static let resolvedAt = "geo_country_resolved_at"
    }

    private static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60

    private let client: HTTPClient
    private let store: any KeyValueStoring
    private let logger = AppLogger(category: .networking)

    private var resolvedCode: String?
    private var mobileOtpEnabled: Bool?
    private var inFlight: Task<String?, Never>?

    init(client: HTTPClient, store: any KeyValueStoring) {
        self.client = client
        self.store = store
    }

    /// Best answer available right now (`countryCode` getter).
    var countryCode: String? { resolvedCode ?? Self.offlineCountryCode() }

    /// `isMobileOtpEnabled`: the server's verdict if known, else derived from
    /// the country, else `true` while the country is unknown.
    var isMobileOtpEnabled: Bool {
        if let mobileOtpEnabled { return mobileOtpEnabled }
        guard let code = countryCode else { return true }
        return Self.mobileOtpCountries.contains(code)
    }

    /// `countryFromDevice` — pure, exposed for tests. India's UTC+05:30 is
    /// shared with Sri Lanka, which the locale region disambiguates.
    nonisolated static func countryFromDevice(offsetMinutes: Int, localeRegion: String?) -> String? {
        if offsetMinutes == indiaOffsetMinutes {
            return localeRegion == "LK" ? "LK" : "IN"
        }
        if let localeRegion, localeRegion.count == 2 { return localeRegion }
        return nil
    }

    nonisolated static func offlineCountryCode(
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        now: Date = Date()
    ) -> String? {
        countryFromDevice(
            offsetMinutes: timeZone.secondsFromGMT(for: now) / 60,
            localeRegion: locale.region?.identifier.trimmingCharacters(in: .whitespaces).uppercased()
        )
    }

    /// `resolve()` — concurrent callers share one in-flight resolution.
    func resolve() async -> String? {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.performResolve() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func performResolve() async -> String? {
        if let cached = cachedCountry() {
            resolvedCode = cached
            mobileOtpEnabled = store.string(forKey: Key.mobileOtp).map { $0 == "true" }
            return cached
        }

        let offline = Self.offlineCountryCode()
        if let offline, offline == "IN" || offline == "LK" {
            resolvedCode = offline
            let enabled = Self.mobileOtpCountries.contains(offline)
            mobileOtpEnabled = enabled
            cache(code: offline, mobileOtpEnabled: enabled)
            return offline
        }

        do {
            let response = try await client.send(.geoCountry)
            if response.statusCode == 200,
               let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
               let raw = object["countryCode"] as? String {
                let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
                if code.count == 2 {
                    let enabled = (object["mobileOtpEnabled"] as? Bool) ?? Self.mobileOtpCountries.contains(code)
                    resolvedCode = code
                    mobileOtpEnabled = enabled
                    cache(code: code, mobileOtpEnabled: enabled)
                    return code
                }
            }
        } catch {
            logger.warning("country server fallback failed: \(error)")
        }

        resolvedCode = offline
        return offline
    }

    private func cachedCountry() -> String? {
        guard let code = store.string(forKey: Key.country), code.count == 2,
              let at = store.string(forKey: Key.resolvedAt).flatMap(Double.init) else { return nil }
        let age = Date().timeIntervalSince1970 * 1000 - at
        guard age >= 0, age <= Self.cacheTTL * 1000 else { return nil }
        let currentOffset = TimeZone.current.secondsFromGMT() / 60
        guard store.string(forKey: Key.offset).flatMap(Int.init) == currentOffset else { return nil }
        return code
    }

    private func cache(code: String, mobileOtpEnabled: Bool) {
        store.setString(code, forKey: Key.country)
        store.setString(mobileOtpEnabled ? "true" : "false", forKey: Key.mobileOtp)
        store.setString(String(TimeZone.current.secondsFromGMT() / 60), forKey: Key.offset)
        store.setString(String(Int(Date().timeIntervalSince1970 * 1000)), forKey: Key.resolvedAt)
    }
}
