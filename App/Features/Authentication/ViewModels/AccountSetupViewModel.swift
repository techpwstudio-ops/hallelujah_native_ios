import Observation

enum AccountSetupFlowState: Equatable {
    case idle
    case loading
    case success
    case error(message: String)
}

/// Ported from the details-step half of `AccountSetupPageState`
/// (`account_setup_page.dart`) — just `_submitDetails`'s network call and its
/// in-flight state. Field state (name/date/gender) and validation stay in
/// `AccountSetupView`, same split `PhoneAuthView`/`EmailAuthView` already use
/// with their own view models.
@MainActor
@Observable
final class AccountSetupViewModel {
    private(set) var state: AccountSetupFlowState = .idle

    private let authRepository: any AuthRepository
    private let currentUserStore: CurrentUserStore
    private let logger = AppLogger(category: .authentication)

    init(container: DependencyContainer = .current) {
        authRepository = container.resolve()
        currentUserStore = container.resolve()
    }

    /// `initState`'s `initData.addAll(OurSession.instance.user?.toJson() ??
    /// {})` plus `late _SetupStep _step = ...currentStep()...` — the cached
    /// user is already in memory by the time `RootView` shows this screen (it
    /// is exactly what `SplashViewModel.resolveDestination()` read to route
    /// here), so this is a same-tick actor hop, not a real loading state.
    func loadCachedUser() async -> User? {
        await currentUserStore.user
    }

    /// `dateOfBirth` is already the ISO 8601 string `_submitDetails` would
    /// have put in `initData['dateOfBirth']` — callers build it from the
    /// picked `Date`, matching `date.toIso8601String()`.
    func submitDetails(fName: String?, lName: String?, dateOfBirth: String, gender: String) async {
        state = .loading

        // `initData['name'] = "${initData['fName'] ?? "User"} ${initData['lName'] ?? ''}"`.
        let name = "\(fName ?? "User") \(lName ?? "")"

        do {
            try await authRepository.updateProfile(name: name, fName: fName, lName: lName, dateOfBirth: dateOfBirth, gender: gender)
            state = .success
        } catch let error as AuthOTPError {
            state = .error(message: error.message)
        } catch {
            logger.warning("account setup save failed: \(error)")
            // Dart only reports this to analytics (`trackError`); no toast.
            state = .idle
        }
    }
}
