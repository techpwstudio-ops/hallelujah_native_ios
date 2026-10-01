import Foundation

enum SupportRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

/// Ports the two `/support/*` endpoints `HelpSupportDashboardScreen`'s FAQ
/// and Feedback tabs call (`faqProvider.dart`'s `fetchFaqs`,
/// `feedback.dart`'s `_onSubmit`). Deliberately separate from
/// `AccountRepository`: these two are plain content/mutation calls needing
/// only an `HTTPClient`, while account deletion also needs `Session`/
/// `CurrentUserStore` to run the sign-out cascade — the same DI-shape split
/// `RemoteFavouriteRepository` (client-only) vs. `RemoteAuthRepository`
/// (client + session + currentUserStore) already draws.
protocol SupportRepository: Sendable {
    /// `FaqNotifier.fetchFaqs` (`faqProvider.dart`) — this rewrite has no
    /// Riverpod-style online/offline auto-retry-on-reconnect layer to port;
    /// `FAQViewModel` (T71) does its own single-attempt load-with-retry-
    /// button instead, matching every other `LoadState`-shaped screen in
    /// this app (e.g. `UserPlaylistDetailViewModel`).
    func fetchFAQs() async throws -> [FAQItem]

    /// `FeedbackPage._onSubmit` (`feedback.dart`) — `title` is the selected
    /// reason's `value` (not always identical to its display label; see
    /// `FeedbackView`'s reason list), `description` the free-text body.
    /// Throws only on a transport failure; a non-200 HTTP response is
    /// returned to the caller as `false` so it can show the server's own
    /// message, matching `_onSubmit`'s `else { showSnackBarToast(message:
    /// res.data['message'] ?? "Failed") }` branch — Dart never throws for a
    /// non-200 here either.
    func submitFeedback(title: String, description: String) async throws -> SubmitFeedbackResult
}

struct SubmitFeedbackResult: Sendable {
    let succeeded: Bool
    /// Server's own message when present. Dart shows a fixed client-side
    /// string ("Feedback submitted successfully") on success rather than
    /// echoing the server's — `createFeedback`'s real 201 body carries
    /// `{message, feedback}`, but `FeedbackView` (T71) follows Dart's own
    /// choice of a fixed success string, keeping `message` only for the
    /// failure path, where Dart does read `res.data['message']`.
    let message: String?
}
