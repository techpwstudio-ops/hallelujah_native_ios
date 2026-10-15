import Foundation

/// Matches the shape of `createSession()` in `lib/utils/session.dart` and the
/// `/auth/token/refresh` response body — same 4 fields, same wire key for the
/// access token (`token`, not `accessToken`).
struct AuthTokens: Sendable, Equatable, Codable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiry: Date
    let refreshTokenExpiry: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "token"
        case refreshToken
        case accessTokenExpiry
        case refreshTokenExpiry
    }
}

extension JSONEncoder {
    static var authTokens: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var authTokens: JSONDecoder {
        let decoder = JSONDecoder()
        // Not bare `.iso8601`: the backend serialises expiries with
        // fractional seconds (`2024-01-10T08:30:00.000Z`), which that
        // strategy rejects, while `DateTime.parse` in Dart takes both.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Date.parseFlexibleISO8601(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a valid ISO 8601 date: \(string)")
            }
            return date
        }
        return decoder
    }
}
