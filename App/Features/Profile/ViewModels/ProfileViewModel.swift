import Foundation
import Observation

enum ProfileFlowState: Equatable {
    case idle
    case loading
    case success
    case error(message: String)
}

/// Ported from `ProfilePageState` (`lib/views/profile/profile_page.dart`) —
/// the network half only. Field state (name/date/gender), change-tracking
/// (`checkChanges`), and the wheel-date-picker/gender-radio UI all live in
/// `ProfileView`, the same split `AccountSetupViewModel`/`AccountSetupView`
/// already use (see that view model's own doc comment).
@MainActor
@Observable
final class ProfileViewModel {
    private(set) var state: ProfileFlowState = .idle

    private let authRepository: any AuthRepository
    private let uploadRepository: any UploadRepository
    private let currentUserStore: CurrentUserStore
    // No dedicated `.profile` `LogCategory` exists yet (adding one is out of
    // this task's file scope) — `.authentication` is the category
    // `AccountSetupViewModel` already logs the same `updateProfile`/
    // `fetchCurrentUser` calls under, so this reuses it rather than
    // introducing a new case for a single call site.
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        authRepository = container.resolve()
        uploadRepository = container.resolve()
        currentUserStore = container.resolve()
    }

    /// `initData.addAll(OurSession.instance.user?.toJson() ?? {})` — the
    /// cached user is already in memory (this screen is only reachable from
    /// inside the signed-in shell), so this is a same-tick actor hop, not a
    /// real loading state. Same shape as `AccountSetupViewModel.loadCachedUser`.
    func loadCachedUser() async -> User? {
        await currentUserStore.user
    }

    /// `initState`'s background refresh:
    /// `OurSession.instance.fetchUserDetails().then((_) { setState(...) })`
    /// — fired once after the cached user is already on screen so profile
    /// always shows the latest server data, but never blocks or fails the
    /// screen. Errors are swallowed here (`fetchCurrentUser`'s own doc
    /// comment already documents this tolerance for background refreshes;
    /// a 403/404 still logs the session out inside the repository itself).
    /// Returns the refreshed `User` on success, `nil` on any failure so the
    /// caller can leave already-edited fields alone.
    func refreshUser() async -> User? {
        try? await authRepository.fetchCurrentUser()
    }

    /// `_submitDetails`-equivalent save path — `UpdateUserProfileEvent`'s
    /// handler in Dart posts through the bloc; here it's a direct repository
    /// call, same shape as `AccountSetupViewModel.submitDetails`.
    /// `dateOfBirth` is already the ISO 8601 string the caller built from the
    /// picked `Date` (`date.toIso8601String()`'s native equivalent).
    ///
    /// Returns `true` on success so `ProfileView` can adopt the saved values
    /// as its new unchanged baseline; `false` on failure, with the message
    /// left in `state` for the caller to toast.
    @discardableResult
    func save(fName: String?, lName: String?, dateOfBirth: String, gender: String, imageFileURL: URL? = nil) async -> Bool {
        state = .loading

        // `initData['name'] = "${initData['fName'] ?? "User"} ${initData['lName'] ?? ''}"`.
        let name = "\(fName ?? "User") \(lName ?? "")"

        do {
            // `AuthBloc._updateProfile`: upload the new photo first, then
            // send its S3 key as `image` with the rest of the profile.
            var imageKey: String?
            if let imageFileURL {
                imageKey = try await uploadRepository.upload(fileURL: imageFileURL, kind: .profilePhoto, mimeType: "image/jpeg")
            }
            try await authRepository.updateProfile(name: name, fName: fName, lName: lName, dateOfBirth: dateOfBirth, gender: gender, image: imageKey)
            state = .success
            return true
        } catch let error as UploadError {
            state = .error(message: error.message)
            return false
        } catch let error as AuthOTPError {
            state = .error(message: error.message)
            return false
        } catch {
            logger.warning("profile save failed: \(error)")
            state = .error(message: "Something went wrong. Please try again.")
            return false
        }
    }
}
