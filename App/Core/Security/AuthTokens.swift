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
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
