import SwiftUI

/// T36 — ports `SongLyricsPage` (`lib/views/home/SongLyricsPage.dart`),
/// replacing `FullScreenDestinationView`'s `PlayerRoute.lyrics` placeholder.
/// Reached only from `PlayerLyricsPreviewCard`'s (T35) "View Full Lyrics"
/// button, which already only appears when the current song has
/// transcripts — matching Dart's own identical gate in `SongLyricsDetails`
/// (`lib/widgets/player/lyrics_ui.dart`: `song.transcripts.isEmpty` ->
/// `SizedBox.shrink()`), so this screen is unreachable with none.
///
/// Dart's `SongLyricsPage` also takes a `TranscriptRepositoryModel?` route
/// argument — a real nested-per-language Dart domain model
/// (`SongRepositoryModel.dart`: `Song.transcripts: List<TranscriptRepositoryModel>`,
/// each wrapping `content: TranscriptContent{meta, type, lines}`), selected
/// by `SongLyricsDetails` via `transcripts.firstWhere(language == userLang,
/// orElse: first)` before ever reaching this screen. Native's existing
/// `Song.transcripts: [LyricsTranscript]?` (`Song.swift`) already flattened
/// that away before this task — a pre-existing simplification, not
/// revisited here since T36's own roadmap text doesn't ask for
/// multi-language selection. `PlayerRoute.lyrics(songTitle:)`'s own doc
/// comment already anticipated this: "whatever builds the player can
/// source the transcript for the song already playing from its own
/// playback state instead of threading it through navigation" — so this
/// view reads `AudioEngine.currentSong?.transcripts` live via DI instead of
/// through the route.
struct SongLyricsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var engine: AudioEngine = DependencyContainer.current.resolve()
    let songTitle: String

    private static let topAnchorID = "top"
    private static let playPauseDiameter: CGFloat = 48
    private static let playGlyphSize: CGFloat = 24
    private static let lineSpacing: CGFloat = 12
    private static let scrollDuration: TimeInterval = 0.35
    private static let lineAnimationDuration: TimeInterval = 0.28
    private static let activeScale: CGFloat = 1.06
    private static let maskFadeFraction: CGFloat = 0.02

    private var lines: [LyricsTranscript] { engine.currentSong?.transcripts ?? [] }

    /// `_onPositionChanged` (`SongLyricsPage.dart:86-93`) and
    /// `_updateForSeconds` (`lyrics_preview.dart`) both use
    /// `lines.lastIndexWhere((l) => l.start <= seconds)` — the LAST line
    /// whose start has passed, ignoring `end` entirely, so a line stays
    /// highlighted until the next one starts even past its own `end`.
    /// `nil` (Dart's `-1`) is valid: before the first lyric.
    private var activeIndex: Int? {
        var result: Int?
        for (index, line) in lines.enumerated() where engine.currentPosition >= line.startTime {
            result = index
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Self.lineSpacing) {
                        Color.clear.frame(height: 0).id(Self.topAnchorID)
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            let isActive = index == activeIndex
                            let isPast = activeIndex.map { index < $0 } ?? false
                            lineView(line, isActive: isActive, isPast: isPast)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, Spacing.md)
                }
                .mask(edgeFadeMask)
                .onChange(of: activeIndex) { _, newValue in
                    withAnimation(.easeOut(duration: Self.scrollDuration)) {
                        if let newValue, lines.indices.contains(newValue) {
                            proxy.scrollTo(lines[newValue].id, anchor: UnitPoint(x: 0.5, y: 0.4))
                        } else {
                            proxy.scrollTo(Self.topAnchorID, anchor: .top)
                        }
                    }
                }
            }

            VStack(spacing: Spacing.lg) {
                SeekBar(
                    position: engine.currentPosition,
                    duration: engine.currentItemDuration ?? TimeInterval(engine.currentSong?.duration ?? 0)
                ) { target in
                    engine.seek(to: target)
                }
                playPauseButton
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .padding(.horizontal, Spacing.lg)
        .background(theme.color(.backgroundPrimary).ignoresSafeArea())
        .navigationTitle(songTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `LyricsLineItem` (`lib/widgets/player/lyrics_line_item.dart`): tap
    /// any line to seek there (`PlayerSeekEvent(Duration(seconds: line
    /// .start))`); `AnimatedScale` 1.06 on active, `AnimatedDefaultTextStyle`
    /// both over 280ms `easeOutCubic`; active/past = full opacity white,
    /// future = 38% opacity; `titleMedium`/bold/1.4 line height (Dart's
    /// `w700` is one step bolder than this design system's own
    /// `Typography.titleMedium`, which is `.semibold` — matched here with
    /// an explicit `.bold` override rather than changing the shared token).
    private func lineView(_ line: LyricsTranscript, isActive: Bool, isPast: Bool) -> some View {
        Text(line.text ?? "")
            .typography(Typography.titleMedium)
            .fontWeight(.bold)
            .multilineTextAlignment(.center)
            .foregroundStyle(theme.color(.textPrimary).opacity(isActive || isPast ? 1 : 0.38))
            .scaleEffect(isActive ? Self.activeScale : 1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { engine.seek(to: line.startTime) }
            .animation(.easeOut(duration: Self.lineAnimationDuration), value: isActive)
    }

    /// `CustomShadedMask` (`lib/widgets/widgets.dart:198-223`): a
    /// top/bottom `ShaderMask` fading over the first/last 2% of the list.
    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: Self.maskFadeFraction),
                .init(color: .black, location: 1 - Self.maskFadeFraction),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// `PlayPauseIconFilled` at `SongLyricsPage.dart`'s call site takes no
    /// width/height override, so it falls back to the class's own default
    /// box (`widgets/icons.dart`: `width: 48, height: 48, size: 32`) — a
    /// smaller button than the full player's 58×58 one
    /// (`player_controls.dart:30-59` explicitly overrides to 58).
    private var playPauseButton: some View {
        Button {
            if engine.status == .playing { engine.pause() } else { engine.resume() }
        } label: {
            ZStack {
                Circle().fill(theme.color(.textPrimary))
                theme.icon(engine.status == .playing ? .pause : .play)
                    .font(.system(size: Self.playGlyphSize))
                    .foregroundStyle(theme.color(.backgroundPrimary))
            }
            .frame(width: Self.playPauseDiameter, height: Self.playPauseDiameter)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: engine.status)
    }
}
