import Foundation

/// Request body shared by `/auth/otp/send` and `/auth/otp/resend`
/// (`AuthOtpService.send`,
/// `lib/features/authentication/data/auth_otp_service.dart`).
///
/// `refer` is `{initial, latest}` deep-link attribution
/// (`ReferralAttributionStore`), sent on first send only (`if (!resend)`).
struct AuthOTPSendRequest: Encodable, Sendable {
    let identifier: String
    let secret1: String
    let secret2: String
    let appCheck: String?
    let requestId: String?
    var refer: ReferAttribution? = nil
}

/// What `/auth/otp/send` and `/auth/otp/resend` answer with.
struct AuthOTPSendResult: Decodable, Sendable, Equatable {
    /// The server-normalised identifier (lower-cased email / stripped E.164
    /// number) — every later call, including `verifyOTP`, must use THIS
    /// value, not the raw text the user typed, or the OTP lookup misses.
    let identifier: String
    /// `email` or `mobile` — which channel the server actually used.
    let channel: String
    /// Absent on a mobile resend, where the gateway re-delivers the code it
    /// already holds and the original expiry still stands.
    let expiryInMinutes: Int?

    var isMobile: Bool { channel == "mobile" }
}

/// Request body for `/auth/otp/verify`.
struct AuthOTPVerifyRequest: Encodable, Sendable {
    let identifier: String
    let otp: String
    let secret1: String
    let secret2: String
    let appCheck: String?
    let requestId: String?
}

/// The full flat `/auth/otp/verify` response body —
/// `AuthBloc.performUpdateAuth`'s `json` parameter
/// (`lib/blocs/auth/bloc.dart`). Tokens (`token`/`refreshToken`/
/// `accessTokenExpiry`/`refreshTokenExpiry`) sit at the same top level as
/// `user`/`isNewUser`/`requiresAccountSetup`, not nested — `AuthTokens`'s
/// own `CodingKeys` already match those four keys, so decoding it a second
/// time from the same container picks them up for free.
///
/// `isPasswordSet` also arrives in this body but isn't modeled: it is the
/// same legacy field `User` already declines to port (see `User.swift`).
/// `deviceId` IS read — `createSession(deviceId:)` persists it and every
/// later request echoes it as the `device-id` header (`DeviceIdentityStore`).
/// `membership` (T61) IS modeled — `OurSession.setMembershipDetails`'s
/// counterpart, `Membership` decodes directly (it's already `Codable`), no
/// separate DTO.
struct AuthOTPVerifyResponse: Sendable, Equatable {
    let tokens: AuthTokens
    let user: User
    let isNewUser: Bool
    let requiresAccountSetup: Bool
    let membership: Membership?
    var deviceId: String? = nil
}

extension AuthOTPVerifyResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case user, isNewUser, requiresAccountSetup, membership, deviceId
    }

    /// Decode with `JSONDecoder.authTokens` (`.iso8601` date strategy) — the
    /// nested `AuthTokens(from:)` call below relies on the decoder carrying
    /// that strategy, same as decoding `AuthTokens` on its own already does.
    /// `membership`'s own dates don't depend on this — `Membership`'s custom
    /// `init(from:)` parses them itself regardless of decoder strategy (see
    /// its own doc comment).
    init(from decoder: Decoder) throws {
        tokens = try AuthTokens(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(User.self, forKey: .user)
        isNewUser = try container.decodeIfPresent(Bool.self, forKey: .isNewUser) ?? false
        requiresAccountSetup = try container.decodeIfPresent(Bool.self, forKey: .requiresAccountSetup) ?? false
        membership = try container.decodeIfPresent(Membership.self, forKey: .membership)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
    }
}

/// The `/users/me` response envelope — `OurSession.updateUserModel`'s
/// `map['user']` read (`lib/utils/session.dart`). `membership` (T61) is the
/// same field `getUserMembershipDetails` populates on every user-fetching
/// endpoint, including this one.
struct CurrentUserResponse: Decodable, Sendable {
    let user: User
    let membership: Membership?
}

/// A refusal from the sign-in flow (`AuthOtpException`), carrying the
/// machine-readable `code` the caller should branch on rather than the
/// message.
///
/// Known codes: `mobile_otp_unsupported` (see `shouldFallBackToEmail`),
/// `account_blocked`, `otp_rate_limited` (see `retryAfterSeconds`),
/// `otp_invalid`, `network_error`.
struct AuthOTPError: Error, Sendable, Equatable {
    let message: String
    let code: String?
    let retryAfterSeconds: Int?
    let fallbackChannel: String?

    var shouldFallBackToEmail: Bool { code == "mobile_otp_unsupported" }

    /// `AuthOtpException.fromResponse` — `JSONSerialization`, not `Codable`:
    /// an error page or empty 5xx body isn't valid JSON at all, and a
    /// malformed error body must never itself throw a second, more
    /// confusing error on top of whatever already went wrong.
    init(statusCode: Int?, data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rawMessage = (json["message"] as? String)?.trimmingCharacters(in: .whitespaces)
        message = (rawMessage?.isEmpty == false ? rawMessage : nil) ?? Self.defaultMessage(for: statusCode)
        code = json["code"] as? String
        retryAfterSeconds = Self.asInt(json["retryAfterSeconds"])
        fallbackChannel = json["fallbackChannel"] as? String
    }

    private static func defaultMessage(for statusCode: Int?) -> String {
        switch statusCode {
        case 401: "Invalid or expired code. Please try again."
        case 422: "Enter a valid email address, or a mobile number including its country code."
        case 429: "Please wait before requesting another code."
        default: "Something went wrong. Please try again."
        }
    }

    /// `AuthOtpService.asInt` — `expiryInMinutes`/`retryAfterSeconds` have
    /// arrived as a JSON string in production before now (server read an env
    /// var without coercing it); this stays lenient rather than trusting the
    /// contract is a number.
    private static func asInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
