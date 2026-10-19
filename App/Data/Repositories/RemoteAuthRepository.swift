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
            requestId: requestID,
            refer: resend ? nil : ReferralAttributionStore.shared.snapshot
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

        // `createSession(deviceId:)` — echoed back as the `device-id` header.
        DeviceIdentityStore.shared.update(decoded.deviceId)
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
            provider: SocialAuthVerifyRequest.Provider(name: provider.rawValue, secrete: secrete),
            refer: ReferralAttributionStore.shared.snapshot
        )
        let body = try JSONEncoder().encode(request)
        let response = try await client.send(.authOAuthVerify, body: body)
        guard response.statusCode == 200 else {
            throw AuthOTPError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder.authTokens.decode(AuthOTPVerifyResponse.self, from: response.data)

        // `createSession(deviceId:)` — echoed back as the `device-id` header.
        DeviceIdentityStore.shared.update(decoded.deviceId)
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
    func updateProfile(name: String, fName: String?, lName: String?, dateOfBirth: String, gender: String, image: String?) async throws -> User {
        let request = AccountSetupProfileRequest(name: name, fName: fName, lName: lName, dateOfBirth: dateOfBirth, gender: gender, image: image)
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

        // The rest of `changeContentLanguages`: re-run the push topic sync
        // (FCM subscriptions can only be moved by the device), wipe the
        // cached home layouts so the next load is in the new language, and
        // refresh `/dashboard/init` (books, genres, languages, topics).
        await FCMTopicManager.shared.contentLanguagesDidChange()
        if let homeCache = DependencyContainer.current.resolveIfRegistered(HomeFeedCache.self) {
            for type in [HomeContentType.all, .music, .episode] {
                await homeCache.clear(type: type)
            }
        }
        Task { await AppDataSync.shared.sync(force: true, silent: true) }
    }

    /// A 403 means the access token was refused (the session expired), so the
    /// refresh token gets one chance before the session is declared over:
    /// refresh, then ask again. The user is signed out only when the refresh
    /// itself is refused (`Session` logs out on its own then) or the retried
    /// call is still 403. A 404 (account deleted) ends the session straight
    /// away, matching `fetchUserDetails()`'s "Check for account deletion or
    /// access issues" branch.
    ///
    /// Every other failure — 5xx, a decode failure, a network error, a refresh
    /// that couldn't be reached — never signs the user out; it is left for the
    /// caller to catch and ignore if it wants Dart's background-refresh
    /// tolerance. `fetchUserDetails(background: true)` swallows those rather
    /// than surfacing an error toast over an app that already loaded fine from
    /// cache, and `verifyOTP` above relies on exactly that tolerance via `try?`.
    @discardableResult
    func fetchCurrentUser() async throws -> User {
        var response = try await client.send(.currentUser)

        if response.statusCode == 403 {
            logger.warning("current user refused (403); trying the refresh token once")
            do {
                try await session.refreshIfNeeded()
            } catch {
                guard Session.endsSession(after: error) else { throw error }
                // The refresh token was refused or has lapsed — `Session` has
                // already logged out; only the cached user is left to drop.
                logger.warning("refresh refused after 403; signed out")
                await currentUserStore.clear()
                throw AuthRepositoryError.accountUnavailable(statusCode: 403)
            }
            response = try await client.send(.currentUser)
        }

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
        await logout(reason: "manual")
    }

    /// `OurSession.logout(reason:)`: an audit entry (`_trackLogoutEvent`) and
    /// the server-side logout (`GET /user/logout?delete=<reason>`) are both
    /// fire-and-forget — errors are logged, never surfaced or allowed to block
    /// the local teardown.
    func logout(reason: String) async {
        let userID = await currentUserStore.user?.id
        let deviceID = DeviceIdentityStore.shared.deviceID
        let client = client
        let logger = logger
        Task.detached {
            let deviceValue: Any = deviceID ?? NSNull()
            let userValue: Any = userID ?? NSNull()
            let metadata: [String: Any] = ["reason": reason, "deviceId": deviceValue]
            let payload: [String: Any] = [
                "action": "logout",
                "entity": "user_session",
                "entityId": userValue,
                "metadata": metadata,
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            do {
                _ = try await client.send(.auditLog, body: body)
            } catch {
                logger.warning("logout audit entry failed: \(error)")
            }
        }

        do {
            let response = try await client.send(.logout(reason: reason))
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
