import Foundation

/// Ports `UserModel` (`lib/models/user_model.dart`).
///
/// `isPasswordSet` is deliberately not ported: Dart's own doc comment calls
/// it "legacy... no longer part of deciding whether an account is set up",
/// kept only for password-management screens that aren't in progress.md —
/// porting it would give `User` a `KeyValueStoring` dependency for a field
/// nothing in this rewrite reads.
struct User: Sendable, Equatable, Identifiable, Codable {
    let id: String
    var name: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var mobile: String?
    var image: String?
    var imageVariants: String?
    /// The full set driving what content the home feed shows — distinct from
    /// `primaryLanguage` (the one push-notification language, chosen
    /// separately; null means "has not chosen", not "English").
    var languages: String?
    var primaryLanguage: String?
    var bibleLanguage: String?
    var gender: String?
    var dateOfBirth: String?
    var provider: String?
    var deletingDate: String?
    /// Server-side account status: `incomplete` until the setup screen saves
    /// languages, then `active`. Also `suspended`/`blocked`/`deleted`. The
    /// authority on whether setup is still owed — refreshed by every
    /// `/users/me` call, so it can't drift from the server the way a
    /// locally-derived guess can.
    var status: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, email, mobile, image, imageVariants, languages
        case primaryLanguage, bibleLanguage, gender, dateOfBirth, provider
        case deletingDate, status, createdAt, updatedAt
        case firstName = "fName"
        case lastName = "lName"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Some endpoints answer with a numeric id — same defensiveness as
        // `UserModel.fromJson`'s `json['id']?.toString()`.
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        mobile = try container.decodeIfPresent(String.self, forKey: .mobile)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        imageVariants = try container.decodeIfPresent(String.self, forKey: .imageVariants)
        languages = try container.decodeIfPresent(String.self, forKey: .languages)
        primaryLanguage = try container.decodeIfPresent(String.self, forKey: .primaryLanguage)
        bibleLanguage = try container.decodeIfPresent(String.self, forKey: .bibleLanguage)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        deletingDate = try container.decodeIfPresent(String.self, forKey: .deletingDate)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        createdAt = Date.parseFlexibleISO8601(try container.decodeIfPresent(String.self, forKey: .createdAt))
        updatedAt = Date.parseFlexibleISO8601(try container.decodeIfPresent(String.self, forKey: .updatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(mobile, forKey: .mobile)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(imageVariants, forKey: .imageVariants)
        try container.encodeIfPresent(languages, forKey: .languages)
        try container.encodeIfPresent(primaryLanguage, forKey: .primaryLanguage)
        try container.encodeIfPresent(bibleLanguage, forKey: .bibleLanguage)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(deletingDate, forKey: .deletingDate)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(createdAt.map(User.isoFormatter.string(from:)), forKey: .createdAt)
        try container.encodeIfPresent(updatedAt.map(User.isoFormatter.string(from:)), forKey: .updatedAt)
    }

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
}

extension User {
    var isAppleProvider: Bool { provider == "apple" }

    /// Whether the user still owes us the account-setup screen.
    ///
    /// `status` is the server's own answer and is preferred whenever
    /// present — the same value the auth endpoints report as
    /// `requiresAccountSetup`. The field checks are the fallback for a
    /// cached user row from a build that predates this field, and are also
    /// the tie-breaker: a cached `status` of "incomplete" alongside every
    /// setup-collected field already filled in is self-contradicting (the
    /// cache lagging the server), so both signals must agree before trusting
    /// "incomplete".
    var needsAccountSetup: Bool {
        let fieldsIncomplete = name == nil || dateOfBirth == nil || languages == nil || gender == nil
        if let status, !status.isEmpty {
            return status == "incomplete" && fieldsIncomplete
        }
        return fieldsIncomplete
    }

    /// NOTE: deliberately not gated on `isPasswordSet` — see this file's
    /// top-level doc comment on why that field isn't ported at all.
    var isAccountSet: Bool { !needsAccountSetup }

    /// `1` = name/dateOfBirth/gender still missing, `2` = languages still
    /// missing, `nil` = setup complete.
    var currentStep: Int? {
        if name == nil || dateOfBirth == nil || gender == nil { return 1 }
        if languages == nil { return 2 }
        return nil
    }
}
