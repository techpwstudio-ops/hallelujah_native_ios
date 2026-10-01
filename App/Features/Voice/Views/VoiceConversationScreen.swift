import SwiftUI

/// T59 — ports `AiAudioConversationPage`
/// (`lib/views/ai/ai_audio_conversation_page.dart`). Full-screen, always-
/// listening voice conversation — the live, in-scope voice UI (see
/// `VoiceController`'s own doc comment and `voice_feature_flag.dart`'s
/// `useStreamingVoice = true`). The legacy `AiVoiceOverlayPage`/
/// `voiceConversationProvider` pairing — the *other* consumer of this page's
/// shared `AiVoiceOverlay` widget in Dart — is a separate, on-device-only
/// voice system not under `lib/features/voice/**` and is out of scope for
/// this port.
///
/// The screen owns nothing but pixels, exactly like the page it ports: the
/// microphone, socket, speech queue and audio session all belong to
/// `VoiceController` (`@State private var voice = VoiceController()`, the
/// same per-screen-owned-controller idiom `ReaderView` uses for
/// `ReaderViewModel`); this view only calls `start()` when it appears and
/// `stop()` when it goes away.
///
/// Presented as `FullScreenDestination.aiAudioConversation(conversationID:)`
/// via `AppNavigationCoordinator.presentAIAudioConversation(conversationID:)`
/// — both already exist and need no changes. The one remaining wiring point
/// is `AppShellView`'s `destinationRoot` switch, which still renders a
/// placeholder for this case — see this task's deferred-patch notes.
///
/// ## Scoped out: the locale picker
///
/// Dart's `_pickLocale()`/`_VoiceLocaleSheet` (a reply-language picker sheet,
/// `_voiceLanguageNames` + friends) is present in the source file but dead:
/// nothing in `build()` calls `_pickLocale()`, and `AiVoiceOverlay`'s
/// constructor has no callback slot for one either — confirmed by reading
/// the full file and grepping every call site of `_pickLocale` in it; the
/// only match is its own declaration. It is not reachable from any gesture
/// or button in the reference app, so porting it here would add a feature
/// Dart's own UI does not actually expose, not port one that exists.
///
/// ## Adaptation versus the Dart original
///
/// Dart's three close paths collapse to two here. `_onLeft()` (the back
/// gesture) exists because Flutter's `PopScope` distinguishes "the route was
/// popped by a gesture" from every other teardown reason, and Dart's own
/// `dispose()` explains why it *also* stops the session there: "If this
/// route went away by some path other than a close handled here, the
/// microphone would otherwise stay open with no UI attached." `.fullScreenCover`
/// has no swipe-to-dismiss gesture of its own (unlike a Flutter page route's
/// back gesture, or SwiftUI's own `.sheet`), so there is no separate
/// "gesture already popped this" case to distinguish from every other
/// teardown reason — `onDisappear` below is the one safety net for any
/// teardown that isn't `closeNow`/the state listener, which is exactly the
/// role Dart's `dispose()` already described itself as playing.
///
/// Dart observes the active→inactive transition via `ref.listen` plus an
/// `addPostFrameCallback` fallback for a session that ended between the
/// listener attaching and the next build — a race specific to Riverpod's
/// build-phase rules. SwiftUI's `@Observable` tracking attaches the first
/// time `body` reads `voice.state` (every render does, via `VoiceOverlayView`'s
/// arguments below), and that first render happens before `.task` ever calls
/// `start()` — so there is no equivalent window for the transition to be
/// missed, and a single `.onChange(of:)` — whose built-in old/new comparison
/// already does what Dart's separate `_wasActive` flag existed for — covers
/// the whole thing.
struct VoiceConversationScreen: View {
    /// Continue an existing AI conversation. `nil` starts a new one.
    let conversationID: String?

    @State private var voice = VoiceController()
    /// Guards every close path against firing twice — once from the state
    /// listener and once from a user tap — which would otherwise ask the
    /// coordinator to dismiss a screen that is no longer on top.
    @State private var closing = false

    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter

    var body: some View {
        VoiceOverlayView(
            phase: voice.state.phase,
            audioLevel: voice.state.level,
            transcript: voice.state.partialTranscript.isEmpty
                ? voice.state.transcript
                : voice.state.partialTranscript,
            replyPreview: voice.state.replyText,
            notice: notice,
            onStop: closeNow,
            onClose: closeNow,
            onTapOrb: voice.state.phase == .speaking ? voice.interrupt : nil
        )
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            voice.start(conversationID: conversationID)
        }
        .onDisappear {
            voice.stop()
        }
        // The session ending on its own — stop, a fatal error, the app
        // losing the channel for good — takes this screen with it. Ports
        // the `ref.listen` transition check in `build()`:
        // `previous.isActive && !next.isActive`.
        .onChange(of: voice.state.isActive) { wasActive, isActive in
            if wasActive, !isActive {
                closeWithNotice(voice.state.error?.message ?? voice.state.notice)
            }
        }
    }

    /// Ports `_notice(state)`.
    private var notice: String? {
        if let notice = voice.state.notice, !notice.isEmpty { return notice }
        if voice.state.phase == .reconnecting { return "Reconnecting…" }
        return nil
    }

    /// Ports `_closeWithNotice`.
    private func closeWithNotice(_ notice: String?) {
        guard !closing else { return }
        closing = true
        coordinator.dismissFullScreen()
        if let notice, !notice.isEmpty {
            toastCenter.show(notice)
        }
    }

    /// Ports `_closeNow` — the close (X) icon and the Stop button. Dismisses
    /// immediately rather than waiting on the session to unwind, so a wedged
    /// permission prompt or platform call can never trap the user here.
    private func closeNow() {
        guard !closing else { return }
        closing = true
        coordinator.dismissFullScreen()
        voice.stop()
    }
}
