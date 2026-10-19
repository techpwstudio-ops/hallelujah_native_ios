import Foundation
import SwiftUI

/// T59 — ports `AiVoiceOverlay` (`lib/views/ai/widgets/ai_voice_overlay.dart`)
/// and `EmetOrb` (`lib/views/ai/widgets/emet_orb.dart`).
///
/// ## Adaptation versus the Dart original
///
/// The Dart widget takes a `VoiceLoopPhase` (5 cases: idle/starting/
/// listening/thinking/speaking) rather than the real `VoicePhase` (8 cases)
/// it is actually driven by, because it is shared with a second, legacy
/// voice system (`AiVoiceOverlayPage`/`voiceConversationProvider`) that has
/// its own native `VoiceLoopPhase`-producing state notifier. Native has only
/// the one streaming voice system, so inventing an equivalent second enum
/// here would exist purely to serve a legacy path native doesn't have. This
/// view instead takes the real `VoicePhase` directly and performs the exact
/// same fold internally via `VoiceDisplayPhase.init(_:)`, transcribed
/// verbatim from `AiAudioConversationPage._overlayPhase`. `VoiceLoopPhase`
/// also has a fifth case (`idle`) that Dart's own `_phaseLabel` already
/// renders identically to `starting` ("Starting...") — so `VoiceDisplayPhase`
/// collapses the two, since every real caller of this view already treats
/// them the same.
///
/// Dart drives the orb/wave/timer off three looping `AnimationController`s
/// (`_pulseCtrl` 1600ms reverse-repeat, `_waveCtrl` 1200ms repeat, `_timerCtrl`
/// 1s repeat). There is no controller-based equivalent idiom elsewhere in
/// this codebase yet, so this port uses a single `TimelineView(.animation)`
/// and derives each value from elapsed time — `triangleWave` reproduces the
/// exact 0→1→0 shape a reverse-repeating `AnimationController` produces, so
/// `0.4 + 0.6 * sin(triangleWave(...) * .pi)` matches the Dart pulse level
/// formula exactly. The per-turn timer resets on entering `.listening`,
/// mirroring `didUpdateWidget`'s reset-on-phase-change (which in Dart
/// compares the already-folded `widget.phase`, exactly like `display` here).
struct VoiceOverlayView: View {
    let phase: VoicePhase
    var audioLevel: Double?
    var transcript: String = ""
    var replyPreview: String = ""
    var notice: String?
    let onStop: () -> Void
    let onClose: () -> Void
    /// Only meaningfully wired by the caller while `phase == .speaking`
    /// (mirrors Dart's `onTapOrb: state.phase == VoicePhase.speaking ?
    /// _voice.interrupt : null`) — passing `nil` here makes a tap a no-op
    /// the same way Dart's `GestureDetector(onTap: null)` does.
    var onTapOrb: (() -> Void)?

    @State private var turnStartedAt: Date = .now

    private var display: VoiceDisplayPhase { VoiceDisplayPhase(phase) }
    private var isListening: Bool { display == .listening }
    private var spokenContext: String {
        display == .speaking ? replyPreview : transcript
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            TimelineView(.animation) { timeline in
                overlayBody(now: timeline.date)
            }
        }
        .onChange(of: display) { _, new in
            if new == .listening { turnStartedAt = .now }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            spokenContext.isEmpty ? display.label : "\(display.label). \(spokenContext)"
        )
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func overlayBody(now: Date) -> some View {
        let elapsed = now.timeIntervalSinceReferenceDate
        let pulseLevel = 0.4 + 0.6 * sin(triangleWave(elapsed, period: 1.6) * .pi)
        let orbLevel = (isListening ? audioLevel : nil) ?? pulseLevel
        let waveT = elapsed * (2 * .pi / 1.2)
        let seconds = max(0, Int(now.timeIntervalSince(turnStartedAt)))

        // `Colors.black.withValues(alpha: 0.92)` + `SafeArea` in the Dart
        // original: the background fills edge to edge while its content
        // stays inset. The ignoring-safe-area background already sits
        // behind this in `body`'s `ZStack`, so this `VStack` only needs to
        // lay out normally within whatever safe area SwiftUI already gives
        // it.
        VStack(spacing: 0) {
            header

            if let notice, !notice.isEmpty {
                Text(notice)
                    .multilineTextAlignment(.center)
                    .font(AIColors.font(12))
                    .lineSpacing(3) // height: 1.4 at 12pt
                    .foregroundStyle(voiceGoldColor)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)

            VoiceOrbGlyphView(level: orbLevel, dimmed: display == .thinking)
                .contentShape(Rectangle())
                .onTapGesture { onTapOrb?() }

            Spacer(minLength: 0).frame(height: 32)

            // `AnimatedSwitcher(220ms)` keyed on the phase: cross-fade.
            ZStack {
                Text(display.label)
                    .font(AIColors.font(20, .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .id(display)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.22), value: display)

            Spacer(minLength: 0).frame(height: 8)

            Group {
                if isListening {
                    Text(timerLabel(seconds))
                        .font(AIColors.font(15))
                        .foregroundStyle(.white.opacity(0.54))
                } else if display == .speaking {
                    Text("Just start talking, or tap to interrupt")
                        .font(AIColors.font(13))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }
            .frame(height: 20)

            Spacer(minLength: 0)

            WaveformBarsView(waveT: waveT, level: isListening ? audioLevel : nil, muted: display == .thinking)

            Spacer(minLength: 0).frame(height: 40)

            StopButtonView(action: onStop)

            Spacer(minLength: 0).frame(height: 48)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 40, height: 1)
            EmetWordmarkView()
                .frame(maxWidth: .infinity)
            CloseButtonView(action: onClose)
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
    }

    private func timerLabel(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Reproduces the 0→1→0 shape of a `Duration: 1600ms` `AnimationController`
    /// run with `repeat(reverse: true)`, sampled at `elapsed` seconds.
    private func triangleWave(_ elapsed: TimeInterval, period: TimeInterval) -> Double {
        let t = elapsed.truncatingRemainder(dividingBy: period) / period
        return t < 0.5 ? t * 2 : 2 - t * 2
    }
}

/// The fold `AiAudioConversationPage._overlayPhase` performs at its call
/// site, moved inside the view — see this file's top-level doc comment.
private enum VoiceDisplayPhase: Equatable {
    case starting
    case listening
    case thinking
    case speaking

    init(_ phase: VoicePhase) {
        switch phase {
        case .idle, .error, .preparing, .reconnecting:
            self = .starting
        case .listening:
            self = .listening
        case .transcribing, .thinking:
            self = .thinking
        case .speaking:
            self = .speaking
        }
    }

    var label: String {
        switch self {
        case .starting: String(localized: "Starting...")
        case .listening: String(localized: "Listening...")
        case .thinking: String(localized: "Thinking...")
        case .speaking: String(localized: "Speaking...")
        }
    }
}

// ---------------------------------------------------------------------------
// Emet wordmark — ports `_EmetWordmark`.
// ---------------------------------------------------------------------------

private struct EmetWordmarkView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text("Emet")
                .font(AIColors.font(18, .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 153.0 / 255.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

// ---------------------------------------------------------------------------
// Close button — ports `_CloseButton`. Always leaves the page immediately,
// whatever the loop underneath is doing.
// ---------------------------------------------------------------------------

private struct CloseButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassCircle(interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

// ---------------------------------------------------------------------------
// Emet orb — ports `EmetOrb`/`_Ring`/`_EmetDisc`.
// ---------------------------------------------------------------------------

private struct VoiceOrbGlyphView: View {
    /// Smoothed 0...1 loudness (mic level while listening, a synthetic
    /// breathing value otherwise) — ports `EmetOrb.audioLevel` already
    /// resolved to its effective value (`_orbLevel` in the Dart page plus
    /// `EmetOrb`'s own `level` fallback, folded together by the caller).
    let level: Double
    let dimmed: Bool

    private static let discSize: CGFloat = 80
    private static let midRingSize: CGFloat = 110
    private static let outerRingSize: CGFloat = 140
    private static let boxSize: CGFloat = 180

    var body: some View {
        ZStack {
            Circle()
                .fill(voiceGoldColor.opacity(0.12 * level))
                .frame(width: Self.outerRingSize, height: Self.outerRingSize)
                .scaleEffect(1.0 + 0.35 * level)

            Circle()
                .fill(voiceGoldColor.opacity(0.22 * level))
                .frame(width: Self.midRingSize, height: Self.midRingSize)
                .scaleEffect(1.0 + 0.20 * level)

            disc
        }
        .frame(width: Self.boxSize, height: Self.boxSize)
        .opacity(dimmed ? 0.45 : 1.0)
    }

    private var disc: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(voiceHex: 0xD9A62A), location: 0.0),
                        .init(color: voiceGoldColor, location: 0.55),
                        .init(color: Color(voiceHex: 0x8B5E00), location: 1.0),
                    ]),
                    // Flutter's `Alignment(-0.25, -0.35)` in a -1...1 space ==
                    // `UnitPoint(x: 0.375, y: 0.325)` in SwiftUI's 0...1 space.
                    center: UnitPoint(x: 0.375, y: 0.325),
                    startRadius: 0,
                    endRadius: Self.discSize * 0.95
                )
            )
            .frame(width: Self.discSize, height: Self.discSize)
            // Best-effort approximation of Dart's `BoxShadow(blurRadius: 24 +
            // 12 * level, spreadRadius: 2 + 3 * level)`: SwiftUI's `.shadow`
            // has no spread parameter and its blur does not scale 1:1 with
            // Flutter's, so the radius below is a visual judgment call, not
            // a unit conversion.
            .shadow(color: voiceGoldColor.opacity(0.35 + 0.25 * level), radius: 12 + 6 * level)
            .overlay(
                // Ports `ai_icon.svg` via the same placeholder the bottom
                // nav's AI tab already uses (`IconToken.tabAI`) — both are
                // documented stand-ins for the same not-yet-converted brand
                // glyph, so this keeps the one source of truth Dart's own
                // comment on `EmetOrb` describes.
                Image(IconToken.tabAI.assetName ?? "ai_icon")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(width: Self.discSize * 0.475, height: Self.discSize * 0.475)
            )
    }
}

// ---------------------------------------------------------------------------
// Waveform bars — ports `_WaveformBars`.
// ---------------------------------------------------------------------------

private struct WaveformBarsView: View {
    let waveT: Double
    let level: Double?
    let muted: Bool

    private static let barCount = 9
    private static let minHeight: CGFloat = 6
    private static let maxHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< Self.barCount, id: \.self) { i in
                let phase = (Double(i) / Double(Self.barCount)) * 2 * .pi
                let wave = (sin(waveT + phase) + 1) / 2
                let norm = muted ? 0.08 : wave * min(max(level ?? 1.0, 0.15), 1.0)
                let height = Self.minHeight + (Self.maxHeight - Self.minHeight) * norm

                RoundedRectangle(cornerRadius: 4)
                    .fill(voiceGoldColor.opacity(0.5 + 0.5 * norm))
                    .frame(width: 4, height: height)
                    .padding(.horizontal, 3)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Stop button — ports `_StopButton`.
// ---------------------------------------------------------------------------

private struct StopButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .glassCircle(interactive: true)
                    .contentShape(Circle())

                Text("Stop")
                    .font(AIColors.font(13))
                    .foregroundStyle(.white.opacity(0.54))
            }
        }
        .buttonStyle(.plain)
    }
}

// ---------------------------------------------------------------------------
// Color — the whole overlay is fixed-dark and non-theme-reactive in Dart
// (hardcoded `Colors.black.withValues(alpha: 0.92)` + `ColorTheme.darkGold`,
// `0xFFB8861B`), and no `ColorToken` case matches `darkGold` exactly
// (`ColorToken.brandPrimary` is theme-reactive and resolves to a different
// hex in each scheme). A file-scoped literal is the faithful port; reusing
// `brandPrimary` would make this screen theme-reactive when Dart's isn't.
// ---------------------------------------------------------------------------

private let voiceGoldColor = Color.white

private extension Color {
    init(voiceHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
