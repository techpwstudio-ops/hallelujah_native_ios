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
    @Environment(\.dismiss) private var dismiss
    @State private var engine: AudioEngine = DependencyContainer.current.resolve()
    let songTitle: String

    private static let topAnchorID = "top"
    private static let scrollAnimation = Animation.easeOut(duration: 0.35)

    private var lines: [LyricsTranscript] { engine.currentSong?.transcripts ?? [] }

    /// `lines.lastIndexWhere((l) => l.start <= seconds)`; `nil` (Dart's -1)
    /// is before the first lyric.
    private var activeIndex: Int? {
        var result: Int?
        for (index, line) in lines.enumerated() where engine.currentPosition >= line.startTime {
            result = index
        }
        return result
    }

    var body: some View {
        // `Scaffold` black, body padding fromLTRB(20, 16, 20, 32).
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        Color.clear.frame(height: 0).id(Self.topAnchorID)
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            LyricsLineItem(
                                text: line.text ?? "",
                                isActive: index == activeIndex,
                                isPast: activeIndex.map { index < $0 } ?? false,
                                onTap: { engine.seek(to: line.startTime) }
                            )
                            .id(line.id)
                        }
                    }
                }
                .mask(LyricsEdgeFadeMask())
                .onChange(of: activeIndex) { _, newValue in
                    scroll(proxy, to: newValue)
                }
                .onAppear {
                    // `_onPositionChanged` on the first frame.
                    scroll(proxy, to: activeIndex)
                }
            }

            PlayerSeekBar(
                position: engine.currentPosition,
                duration: engine.currentItemDuration ?? TimeInterval(engine.currentSong?.duration ?? 0),
                barHeight: 4
            ) { target in
                engine.seek(to: target)
            }
            .padding(.top, 16)

            Button {
                if engine.status == .playing { engine.pause() } else { engine.resume() }
            } label: {
                PlayerPlayPauseDisc(
                    isPlaying: engine.status == .playing,
                    isLoading: engine.status == .loading,
                    diameter: 48,
                    glyphSize: 32
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(.leading, PlayerStyle.pageSidePadding)
        .padding(.trailing, PlayerStyle.pageSidePadding)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .background(PlayerStyle.black.ignoresSafeArea())
        .toolbar {
            AppBackToolbarItem { dismiss() }
            ToolbarItem(placement: .principal) {
                Text(songTitle)
                    .typography(Typography.titleMedium)
                    .foregroundStyle(PlayerStyle.white)
                    .lineLimit(1)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(PlayerStyle.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// `_scrollToActiveLine`: `Scrollable.ensureVisible(alignment: 0.4)` over
    /// 350 ms easeOut; before the first lyric, back to the top.
    private func scroll(_ proxy: ScrollViewProxy, to index: Int?) {
        withAnimation(Self.scrollAnimation) {
            if let index, lines.indices.contains(index) {
                proxy.scrollTo(lines[index].id, anchor: UnitPoint(x: 0.5, y: 0.4))
            } else {
                proxy.scrollTo(Self.topAnchorID, anchor: .top)
            }
        }
    }
}
