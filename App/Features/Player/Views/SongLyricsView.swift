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
    /// The shared episode timeline, for the chapter segments on the seek bar.
    @State private var timelineStore: EpisodeTimelineStore = DependencyContainer.current.resolve()
    @State private var songDetailCache: SongDetailCache = DependencyContainer.current.resolve()
    /// Filled from the song's detail when the queue's copy carries no lines.
    @State private var lines: [LyricsTranscript] = []
    let songTitle: String

    /// The playing episode's chapters, as the full player shows them; none for a song, or while the
    /// timeline on hand belongs to another track.
    private var chapters: [EpisodeChapter] {
        guard let id = engine.currentSong?.id, timelineStore.loadedSongId == id else { return [] }
        return timelineStore.chapters
    }

    private static let topAnchorID = "top"
    private static let scrollAnimation = Animation.easeOut(duration: 0.35)


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
                                wordTiming: .of(lines, at: index) { engine.currentPlaybackMs() },
                                onTap: { engine.seek(to: line.startTime) }
                            )
                            .id(line.id)
                        }
                    }
                    // Tablet/Mac: lyric lines keep a readable measure; the
                    // scroll view itself still spans the window.
                    .readableContentWidth()
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
                barHeight: 4,
                chapters: chapters
            ) { target in
                engine.seek(to: target)
            }
            .readableContentWidth()
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
        // Normally already loaded by the full player; a no-op then.
        .task(id: engine.currentSong?.id) { await timelineStore.load(for: engine.currentSong) }
        .task(id: engine.currentSong?.id) {
            let song = engine.currentSong
            let language = await SongDetailCache.preferredLyricsLanguage()
            lines = (song?.transcripts ?? []).inPreferredLanguage(language)
            guard let song else { return }
            let loaded = await songDetailCache.transcripts(for: song, preferredLanguage: language)
            guard !Task.isCancelled, engine.currentSong?.id == song.id else { return }
            lines = loaded
        }
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
