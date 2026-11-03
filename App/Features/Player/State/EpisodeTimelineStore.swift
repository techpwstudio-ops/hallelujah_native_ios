import Foundation
import Observation

/// The episode-only data for the song playing now: chapters, speakers and the
/// transcript. The list-view `Song` the engine holds carries none of it, so the
/// detail is fetched through `SongDetailCache` (I2). Music never loads anything.
/// One instance is shared by the full player and the transcript screen.
@Observable
@MainActor
final class EpisodeTimelineStore {
    private(set) var timeline: EpisodeTimeline?
    private(set) var transcript: EpisodeTranscriptFile?
    private(set) var index: TimelineIndex?
    private(set) var loadedSongId: String?

    let clock: TranscriptClock

    @ObservationIgnored private let cache: SongDetailCache
    @ObservationIgnored private let transcripts: TranscriptRepository

    init(engine: AudioEngine, cache: SongDetailCache, transcripts: TranscriptRepository) {
        self.cache = cache
        self.transcripts = transcripts
        clock = TranscriptClock(engine: engine)
    }

    var chapters: [EpisodeChapter] { timeline?.chapters ?? [] }
    var speakers: [EpisodeSpeaker] { timeline?.speakers ?? [] }

    /// Rule R1: the read-along shows only for a `ready` transcript that has loaded.
    var hasReadAlong: Bool {
        timeline?.transcript.status == .ready && transcript != nil
    }

    /// Two or more speakers, for the speaker headers and the now-speaking chip.
    var hasMultipleSpeakers: Bool { speakers.count >= 2 }

    /// The transcript's `offsetMs`. A word's player time is its file time plus this.
    var offsetMs: Int { timeline?.transcript.offsetMs ?? 0 }

    /// Loads the episode's detail and transcript when the song changes. Music is
    /// cleared at once. A failure leaves the episode with no timeline, and playback is never affected.
    func load(for song: Song?) async {
        guard let song, song.isEpisode else {
            reset()
            return
        }
        guard song.id != loadedSongId else { return }
        reset()
        loadedSongId = song.id

        let detailed = try? await cache.song(id: song.id)
        guard loadedSongId == song.id else { return }
        timeline = detailed?.episodeTimeline
        guard let info = timeline?.transcript, info.status == .ready else {
            index = TimelineIndex(chapters: chapters)
            clock.attach(index)
            return
        }

        let file = await transcripts.transcript(for: info, songId: song.id)
        guard loadedSongId == song.id else { return }
        transcript = file
        index = TimelineIndex(chapters: chapters, transcript: file, offsetMs: info.offsetMs)
        clock.attach(index)
    }

    /// The label the transcript uses for `speaker` and the position it has in
    /// the speakers list. The name is the server's name, or nil for "Speaker N".
    func speakerPosition(forLabel label: String) -> Int? {
        speakers.firstIndex { $0.label == label }
    }

    private func reset() {
        timeline = nil
        transcript = nil
        index = nil
        loadedSongId = nil
        clock.attach(nil)
    }
}
