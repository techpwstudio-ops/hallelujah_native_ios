import Foundation
import Observation

/// The three outcomes `_onSubmit` (`lib/views/support/feedback.dart`)
/// distinguishes with its `try`/`else`/`catch` — kept separate here (rather
/// than collapsing "failure" and "thrown error" into one case) because Dart
/// shows a different message for each: the server's own `message` for a
/// non-200 response, a fixed generic string for a transport failure. Native
/// words the thrown case through `UserFacingError`, so being offline reads as
/// "No internet connection" rather than the generic text.
enum FeedbackSubmitOutcome: Equatable {
    case success
    case failure(message: String?)
    case transportError(message: String)
}

/// Ports `_FeedbackPageState._onSubmit`'s network call and its in-flight
/// state. Reason selection, the reason label/value pairs, validation and the
/// email fallback all stay in `FeedbackView` — this owns only the submit
/// call, same view/view-model split `CreatePlaylistViewModel` draws.
@MainActor
@Observable
final class FeedbackViewModel {
    private(set) var isSubmitting = false

    private let supportRepository: any SupportRepository
    private let logger = AppLogger(category: .content)

    init(container: DependencyContainer = .current) {
        supportRepository = container.resolve()
    }

    /// `title`/`description` are already the selected reason's `value` and
    /// the trimmed free-text body — `FeedbackView.isValid` gates the call
    /// before this is ever reached, so this only guards re-entrancy (a
    /// double-tap while already in flight), same defensive-backstop shape
    /// `CreatePlaylistViewModel.submit` uses. Returns `nil` for that no-op
    /// case; the caller does nothing with it, matching Dart's disabled
    /// Submit button never firing a second in-flight request either.
    func submit(title: String, description: String) async -> FeedbackSubmitOutcome? {
        guard !isSubmitting else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result = try await supportRepository.submitFeedback(title: title, description: description)
            return result.succeeded ? .success : .failure(message: result.message)
        } catch {
            logger.warning("submit feedback failed: \(error)")
            return .transportError(message: UserFacingError.message(for: error))
        }
    }
}
