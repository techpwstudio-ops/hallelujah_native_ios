import Foundation

enum AuthRepositoryError: Error, Sendable, Equatable {
    case accountUnavailable(statusCode: Int)
    case unexpectedStatus(Int)
}

final class RemoteAuthRepository: AuthRepository {
    private let client: HTTPClient
    private let session: Session
    private let currentUserStore: CurrentUserStore
    private let membershipStore: MembershipStore
    private let appCheck: any AppCheckProviding
    private let configuration: AppConfiguration
    private let realtimeConnectionManager: RealtimeConnectionManager
    private let logger = AppLogger(category: .authentication)

    init(
        client: HTTPClient,
        session: Session,
        currentUserStore: CurrentUserStore,
        membershipStore: MembershipStore,
        appCheck: any AppCheckProviding,
        configuration: AppConfiguration,
        realtimeConnectionManager: RealtimeConnectionManager
    ) {
        self.client = client
        self.session = session
        self.currentUserStore = currentUserStore
        self.membershipStore = membershipStore
        self.appCheck = appCheck
        self.configuration = configuration
        self.realtimeConnectionManager = realtimeConnectionManager
    }

    func sendOTP(identifier: String, resend: Bool, requestID: String?) async throws -> AuthOTPSendResult {
        let request = AuthOTPSendRequest(
            identifier: identifier,
            secret1: configuration.otpSecret1,
            secret2: configuration.otpSecret2,
            appCheck: await appCheck.limitedUseToken(),
            requestId: requestID
        )
        let body = try JSONEncoder().encode(request)
        let response = try await client.send(resend ? .authOTPResend : .authOTPSend, body: body)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        return try JSONDecoder().decode(AuthOTPSendResult.self, from: response.data)
    }

    func verifyOTP(identifier: String, otp: String, requestID: String?) async throws -> AuthVerifyOutcome {
        let request = AuthOTPVerifyRequest(
            identifier: identifier,
            otp: otp,
            secret1: configuration.otpSecret1,
            secret2: configuration.otpSecret2,
            appCheck: await appCheck.limitedUseToken(),
            requestId: requestID
        )
        let body = try JSONEncoder().encode(request)
        let response = try await client.send(.authOTPVerify, body: body)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder.authTokens.decode(AuthOTPVerifyResponse.self, from: response.data)

        try await session.store(decoded.tokens)
        await currentUserStore.setUser(decoded.user)
        await membershipStore.setMembership(decoded.membership)
        await realtimeConnectionManager.connect()

        // Re-confirms the account still exists, same as
        // `AuthBloc.performUpdateAuth` calling `fetchUserDetails()` right
        // after `createSession()` — but a failure here that isn't 403/404 is
        // tolerated (see `fetchCurrentUser`'s doc comment), so a slow or
        // offline refresh never undoes the session just stored above.
        let refreshedUser = (try? await fetchCurrentUser()) ?? decoded.user

        return AuthVerifyOutcome(
            user: refreshedUser,
            isNewUser: decoded.isNewUser,
            requiresAccountSetup: decoded.requiresAccountSetup
        )
    }

    func verifySocialAuth(user: SocialAuthUser, provider: SocialAuthProvider, secrete: String) async throws -> AuthVerifyOutcome {
        let request = SocialAuthVerifyRequest(
            user: SocialAuthVerifyRequest.User(
                name: user.name,
                email: user.email,
                image: user.image,
                fName: user.fName,
                lName: user.lName
            ),
            secret1: configuration.otpSecret1,
            secret2: configuration.otpSecret2,
            appCheck: await appCheck.limitedUseToken(),
            isLogin: true,
            provider: SocialAuthVerifyRequest.Provider(name: provider.rawValue, secrete: secrete)
        )
        let body = try JSONEncoder().encode(request)
        let response = try await client.send(.authOAuthVerify, body: body)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder.authTokens.decode(AuthOTPVerifyResponse.self, from: response.data)

        try await session.store(decoded.tokens)
        await currentUserStore.setUser(decoded.user)
        await membershipStore.setMembership(decoded.membership)
        await realtimeConnectionManager.connect()

        // Same background-refresh tolerance as `verifyOTP` above.
        let refreshedUser = (try? await fetchCurrentUser()) ?? decoded.user

        return AuthVerifyOutcome(
            user: refreshedUser,
            isNewUser: decoded.isNewUser,
            requiresAccountSetup: decoded.requiresAccountSetup
        )
    }

    @discardableResult
    func updateProfile(name: String, fName: String?, lName: String?, dateOfBirth: String, gender: String) async throws -> User {
        let request = AccountSetupProfileRequest(name: name, fName: fName, lName: lName, dateOfBirth: dateOfBirth, gender: gender)
        let body = try JSONEncoder().encode(request)
        let response = try await client.send(.userProfileSave, body: body)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        let envelope = try JSONDecoder().decode(CurrentUserResponse.self, from: response.data)
        await currentUserStore.setUser(envelope.user)
        return envelope.user
    }

    func fetchLanguages() async throws -> [LanguageOption] {
        let response = try await client.send(.languages)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        let rows = try JSONDecoder().decode([LanguageOptionDTO].self, from: response.data)
        return rows.compactMap { dto in
            guard let name = dto.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return LanguageOption(name: name, nameNative: dto.nameNative)
        }
    }

    /// Mirrors `OurSession.changeContentLanguages`: the response is a flat
    /// `{languages, primaryLanguage, status}` object, not the `{user: ...}`
    /// envelope `updateProfile`/`fetchCurrentUser` decode, so the cached
    /// `User` is mutated in place rather than replaced wholesale. `status`
    /// is only overwritten when present, same as Dart's `if (status != null
    /// && status.isNotEmpty)` guard — this is what flips a fresh signup from
    /// `incomplete` to `active` server-side, and losing it would write the
    /// stale `incomplete` back to storage and strand the user on account
    /// setup on the next cold launch.
    func saveLanguages(_ languages: [String], primaryLanguage: String?) async throws {
        let request = SaveLanguagesRequest(languages: languages.joined(separator: ","), primaryLanguage: primaryLanguage)
        let body = try JSONEncoder().encode(request)
        let response = try await client.send(.saveLanguages, body: body)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(SaveLanguagesResponse.self, from: response.data)
        guard var user = await currentUserStore.user else { return }
        user.languages = decoded.languages
        user.primaryLanguage = decoded.primaryLanguage
        if let status = decoded.status, !status.isEmpty {
            user.status = status
        }
        await currentUserStore.setUser(user)
    }

    /// A 403/404 logs the session out and throws, matching
    /// `fetchUserDetails()`'s "Check for account deletion or access issues"
    /// branch exactly. Every other failure (network error, 5xx, a decode
    /// failure) is left for the caller to catch and ignore if it wants
    /// Dart's background-refresh tolerance — `fetchUserDetails(background:
    /// true)` swallows those rather than surfacing an error toast over an
    /// app that already loaded fine from cache, and `verifyOTP` above relies
    /// on exactly that tolerance via `try?`.
    @discardableResult
    func fetchCurrentUser() async throws -> User {
        let response = try await client.send(.currentUser)

        if response.statusCode == 403 || response.statusCode == 404 {
            logger.warning("current user unavailable (\(response.statusCode)); logging out")
            await session.logout()
            await currentUserStore.clear()
            throw AuthRepositoryError.accountUnavailable(statusCode: response.statusCode)
        }
        guard response.statusCode == 200 else {
            throw AuthRepositoryError.unexpectedStatus(response.statusCode)
        }

        let envelope = try JSONDecoder().decode(CurrentUserResponse.self, from: response.data)
        await currentUserStore.setUser(envelope.user)
        await membershipStore.setMembership(envelope.membership)
        return envelope.user
    }

    func logout() async {
        // Fire-and-forget, matching `session.dart`'s `logout()`: errors are
        // logged, never surfaced or allowed to block the local teardown.
        do {
            let body = try JSONEncoder().encode(["delete": "manual"])
            let response = try await client.send(.logout, body: body)
            if response.statusCode != 200 {
                logger.warning("logout endpoint returned \(response.statusCode)")
            }
        } catch {
            logger.warning("logout endpoint failed: \(error)")
        }
        await session.logout()
        await currentUserStore.clear()
        await membershipStore.clear()
    }
}
