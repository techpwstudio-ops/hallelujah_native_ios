import Foundation

/// T58 — a tiny cross-screen signal, same shape as `SignOutSignal`
/// (`Core/Security/SignOutSignal.swift`): `@MainActor @Observable`, `Sendable`
/// via main-actor isolation (every stored property is only ever touched on
/// the main actor), no `DependencyContainer`-resolved dependencies of its
/// own to justify an `init(container:)` the way `NetworkStatusStore`/
/// `CurrentUserStore` have.
///
/// `AIChatHistoryView` (a separate pushed screen) sets `pendingConversationID`
/// when the user taps a conversation row; `AIChatHomeView` (the tab root — a
/// different view instance) observes it, switches its active conversation,
/// then clears it back to `nil`. Neither screen can hand the other a direct
/// closure across `AppShellView`'s generic `AppRoute` dispatch (out of
/// bounds for this task to touch), so this shared, observed instance is the
/// bridge — mirrors the Flutter app's own `aiOpenConversationProvider`
/// global-signal workaround for the identical structural reason.
@MainActor
@Observable
final class AIChatNavigationStore: Sendable {
    var pendingConversationID: String?
}
