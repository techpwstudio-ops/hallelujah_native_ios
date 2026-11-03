# Podcast Player: Hallelujah iOS Plan

Status: Draft for review · 3 Nov 2026
Parent plan: `PODCAST_PLAYER_PLAN.md` in the workspace root (goals, design, phases). This file is the Hallelujah iOS slice, checked against the code in this repo.
Other slices: `docs/PODCAST_PLAYER_PLAN.md` in Hallelujah Backend, Hallelujah Flutter, Hallelujah Studio and Hallelujah Admin (`Docs/` here, with a capital D).
Hallelujah Flutter is the same product and the spec for look and behaviour (decision D12 in `progress.md`). Every behaviour below uses the same numbers as its plan, so the two apps match.

File paths and line numbers come from a read-only survey on 3 Nov 2026. Confirm each one when you open the file; lines drift. Paths are relative to `app-ios/`.

## 1. What this repo owns

1. Reading the new episode fields from the existing song detail call.
2. The chapter seekbar, the chapters sheet, the read-along card, the transcript screen, speaker headers and the now speaking chip.
3. Downloading and caching the transcript file.

It adds **no endpoint and no change to music playback**.

Conventions that apply (from `progress.md`): SwiftUI with `@Observable` view models (D1), Swift 6 with strict concurrency (D7), iOS 17 minimum (D3), width-driven layouts through `AdaptiveLayout` (D20), no hardcoded strings, colours or paths, API paths as `Endpoint` values, light and dark previews and unit tests for new code. There is no `CLAUDE.md` in this repo; `progress.md` plays that role. It has uncommitted edits by someone else today (along with `PlaybackAnalyticsUploader.swift`, `NotificationService.swift` and `reopen-session.sh`), so none of those files are touched by this plan until those edits are committed.

## 2. What the code showed that changes the parent plan

| # | Finding | Where | What changes |
| --- | --- | --- | --- |
| I1 | **`AudioEngine` has no way to read the playback time on demand.** The plan assumed one. The only time is `currentPosition`, published every 0.5 s by a periodic observer, with a 1.5 s `pendingSeek` guard after a seek. | `Platform/Audio/AudioEngine.swift` (40, 51, 353, 730–745) | Add one small accessor that reads the private `AVQueuePlayer`'s `currentTime()` and applies the same `pendingSeek` rule. Nothing else in the engine changes. |
| I2 | **Lists do not carry the new fields; the detail call does.** `engine.currentSong` usually comes from a list. The full player already calls `GET /song/:id` on every song change, but keeps the result in the view's local state. Four other places fetch the same detail. | `Features/SongMenu/Components/SongMetaSections.swift` (42), `SongMenuViewModel.swift` (155, 201), `DownloadEngine.swift` (460), `DeepLinkService.swift` (255) | One shared, in-memory `SongDetailCache` (an actor, keyed by song id, in-flight requests coalesced, short TTL) sits in front of `SongRepository.fetchSong`. `SongMetaSections` and the new timeline store both use it, so the player makes one request, not two. No new endpoint. |
| I3 | **`Song` is built with the full memberwise initializer in five places.** Adding stored properties without defaults breaks them. `withFavorited` rebuilds a `Song` field by field and would silently drop anything it does not forward. | `Domain/Entities/Song.swift` (54, 149), `Data/DTOs/ContentDTOs.swift` (289), `Core/Persistence/RecentSearchStore.swift` (54), `Platform/CarPlay/CarPlayContentProvider.swift` (348), `Tests/Support/Fixtures/SongFixture.swift` (20) | Add `var episodeTimeline: EpisodeTimeline? = nil` with a default, so the four other call sites compile unchanged. Update `withFavorited` to forward it, and add a test for that. `Song` is not `Codable`, and `audioUrls` are never persisted; the timeline's signed URL follows the same rule (not stored). |
| I4 | **One malformed new key would fail the whole `Song` decode.** `SongDTO` uses synthesized `Decodable`; a wrongly typed `chapters` throws, and the song fails to load. | `Data/DTOs/ContentDTOs.swift` (216–273, 288–358) | Decode the three new fields leniently: a small `LenientValue<T>` wrapper with a `KeyedDecodingContainer.decode` overload that returns the default for a missing or bad key and drops bad items from arrays. |
| I5 | **The seekbar is shared with the ad-break screen and the lyrics screen.** `PlayerSeekBar` is used at three places. No caller passes `buffered`, so it is always 0 today. | `Features/Player/Components/PlayerSeekBar.swift`, used in `FullPlayerView.swift` (283), `SongLyricsView.swift` (77), `AdBreakView.swift` (439, `isInteractive: false`) | Add `chapters: [ChapterSegment] = []`. With the default the view renders exactly as today. Only `FullPlayerView` passes chapters. |
| I6 | **The engine publishes no buffered range.** The parent plan wants the buffered part drawn lighter. That needs new engine code that nothing uses today. | `AudioEngine.swift` | Not part of this project on iOS (decision D-I2). Chapters do not depend on it. Flutter shows it because it already has the data. |
| I7 | **The "upcoming" lyric style is 38% white, not 50%.** | `Features/Player/Components/LyricsLineItem.swift` | Reuse its colour tokens for the transcript so the two screens match, as Flutter does. |
| I8 | **Ad breaks never overlap the episode.** They run only between tracks, on a separate `AVPlayer`, and `FullPlayerView` swaps in `AdBreakView` while `isAdBreak` is true. | `Platform/Ads/AdPacingController.swift` (119–122, 225–257, 453–475), `FullPlayerView.swift` (69–76) | No mid-episode ad handling. The clock stops when the engine is not `.playing` or an ad break is active. |
| I9 | **`HTTPClient` takes relative paths only and has no HTTP cache.** | `Core/Networking/Client/HTTPClient.swift` (47–48) | The CDN file is fetched with its own `URLSession`, so no app auth headers go to the CDN. |
| I10 | **`UIBackgroundModes` includes audio and the engine keeps playing with the screen off.** `TimelineView(.animation)` and per-frame loops are what the iOS battery history points at. `Docs/PERFORMANCE.md` sets 4% per hour of background playback and notes `FullPlayerView` already re-renders at 2 Hz. | `Docs/PERFORMANCE.md`, `app/docs/ios_battery_drain_analysis.md` | The clock is boundary-driven, not per frame (section 5). |
| I11 | **The parent plan's "one `AttributedString` per paragraph" cannot give per-word tap targets and per-word colours reliably.** A `.link` run takes the tint colour, and iOS 17 has no text-layout hit testing. | parent plan 5.8 | Render a paragraph as a wrapping layout of word views (section 5). Proven in a spike at the start of Phase 2 (decision D-I1). |
| I12 | **Offline downloads rebuild `Song` without the new data.** `makeDownloadedSnapshot` sets `transcripts: nil`. | `Domain/Entities/Song.swift`, `DownloadEngine.swift` | Phase 1 and 2 behave as "no timeline offline unless it was cached". Decision D-I4. |

**Rule R1 (do not regress existing transcripts).** The read-along card shows only when `episodeTranscript.status == "ready"`. Otherwise `metaSection` is exactly as today, including `PlayerLyricsPreviewCard` for episodes that have legacy `transcripts`.

**Rule R2 (minimum chapters).** The chapter UI appears when the episode has **two or more** chapters.

## 3. API contract

This section is copied word for word into the plan of each repo. If it changes, change it in all five. Hallelujah Backend owns it.

### Rules

1. **Existing endpoints keep their path, method, auth and existing fields.** Nothing is renamed, removed or retyped.
2. **New fields are additive and appear for `type = episode` only.** For music, the keys are absent.
3. **Absent means empty.** A client that doesn't find `chapters`, `speakers` or `episodeTranscript` treats them as `[]`, `[]` and `{ "status": "none" }`.
4. **All times are whole milliseconds.**
5. **A kill switch exists.** While the backend settings `episodeChaptersEnabled` / `episodeTranscribeEnabled` are off, the matching fields are absent from every listener-facing response (`/api/song/:songId`, `/web/song/:songId`, `/web/browse/song/:songId`), exactly as if the feature had not shipped. The creator view and the creator endpoints are not affected, so creators can prepare chapters and transcripts before the apps ship.
6. **New endpoints exist only where no existing endpoint can carry the data.** They are listed below. Every other flow reuses what is already there.

### Endpoints

| Who | Endpoint | Change |
| --- | --- | --- |
| Hallelujah Flutter, Hallelujah iOS | `GET /api/song/:songId` | **Additive fields** for episodes (below). Same handler also serves `GET /web/song/:songId` and `GET /web/browse/song/:songId`. |
| Hallelujah Studio | `GET /creator/song/get/:id` | **Additive fields**, plus the creator-only extras below. |
| Hallelujah Studio | `POST /creator/song/publish`, `PATCH /creator/song/:id/update` | **None.** The Joi schema (`publishSongSchema`) is not touched and the pending-changes flow is not touched. |
| Hallelujah Admin | `GET/PUT /admin/song/:id` and the rest of `/admin/song*` | **None.** |
| Hallelujah Admin | The existing settings endpoints | **New keys only** (`episodeChaptersEnabled`, `episodeTranscribeEnabled`, `episodeTranscribeDailyAudioHours`, `episodeTranscribeCostPerHourUsd`). |
| Hallelujah Studio | `PUT /creator/song/:id/chapters` | **New.** Replace the creator's chapters. |
| Hallelujah Studio | `DELETE /creator/song/:id/chapters` | **New.** Drop the creator's chapters; automatic sources take over. |
| Hallelujah Studio | `POST /creator/song/:id/chapters/parse-description` | **New.** Returns suggested chapters from the description. Writes nothing. |
| Hallelujah Studio | `PUT /creator/song/:id/speakers` | **New.** Name the speakers. |
| Hallelujah Studio | `POST /creator/song/:id/transcript` | **New.** Attach the creator's own transcript (VTT, SRT or JSON). |
| Hallelujah Studio | `PATCH /creator/song/:id/transcript` | **New.** `{ "enabled": true \| false }`: show the creator's transcript or the automatic one. |
| Hallelujah Studio | `DELETE /creator/song/:id/transcript` | **New.** Remove the creator's transcript. |
| Hallelujah Admin | `GET /admin/episode-transcripts` | **New.** Transcript jobs, filtered by `status`, `source`, `songId` and title search, paged. |
| Hallelujah Admin | `GET /admin/episode-transcripts/usage` | **New.** Audio hours and cost per day, with the budget. |
| Hallelujah Admin | `POST /admin/episode-transcripts/:songId/queue` | **New.** Queue or retry the automatic transcript. |
| Hallelujah Admin | `PATCH /admin/episode-transcripts/:songId` | **New.** Set `offsetMs` on the transcript users currently see. |

The Studio-side writes are separate endpoints on purpose. `publishSongSchema` rejects keys it doesn't know, and the pending-changes code replays the song payload verbatim on approval, so putting chapters into that payload would put an unrelated feature on the most fragile path in the repo.

### Song detail: new fields (apps, web and Studio)

```json
{
  "id": "…",
  "type": "episode",
  "transcripts": [ "…unchanged, music-lyrics flow…" ],

  "chapters": [
    { "id": "…", "startMs": 0, "endMs": 74000, "title": "Intro", "imageUrl": null, "linkUrl": null }
  ],
  "speakers": [
    { "label": "S1", "name": "Pastor John", "imageUrl": "https://…", "creatorId": "…" },
    { "label": "S2", "name": null, "imageUrl": null, "creatorId": null }
  ],
  "episodeTranscript": {
    "status": "ready",
    "language": "te",
    "source": "asr",
    "autoGenerated": true,
    "version": 2,
    "url": "https://<cdn>/transcripts/<songId>/v2.json?Expires=…&Signature=…",
    "offsetMs": 0
  }
}
```

- `chapters` are sorted by `startMs`. Each `endMs` equals the next chapter's `startMs`; the last one equals the episode's duration. At most 200 per episode, titles at most 120 characters.
- `speakers` lists every label that appears in the transcript file, in the order they first speak. `name` is `null` until someone names the speaker; show "Speaker 1", "Speaker 2" in the app (localized, built from the label's position).
- `episodeTranscript.status` is one of `none`, `queued`, `processing`, `ready`, `failed`. Apps show transcript UI only for `ready`. `url` is `null` for every other status.
- `episodeTranscript.source` is `creator`, `asr` or `publisher`. `autoGenerated` is `true` for `asr` and `publisher`.
- **`url` is a signed CDN URL that expires (about 3 hours), exactly like `audioUrls`.** It is not a permanent address. Apps must cache the file on disk by **`songId` + `version`**, never by URL. If a download of `url` fails with 403, the app fetches the song detail again once and retries with the new URL.
- The apps' existing `transcripts` field (music lyrics) is unchanged and keeps working as before.

**`offsetMs` rule (one rule, used everywhere).** A word's effective time is `file time + offsetMs`. So to find the active word, an app looks up `playerPositionMs - offsetMs` in the file's times. Chapters are not shifted by `offsetMs`.

### Transcript file (`episodeTranscript.url`)

```json
{
  "format": 1,
  "version": 2,
  "language": "te",
  "segments": [
    {
      "speaker": "S1",
      "startMs": 1200,
      "endMs": 6840,
      "words": [[1200, 1460, "Rob,"], [1500, 1910, "thanks"], [1950, 2100, "for"]]
    }
  ]
}
```

- `format` is the schema version of this file. An app that sees a `format` higher than it supports shows no transcript and does not crash. `version` matches `episodeTranscript.version`.
- Words are `[startMs, endMs, text]`, in time order, with no overlaps. Segments are in time order. `speaker` is `null` when the source has no speaker labels.
- Text is Unicode. Apps must split on the words as given and never on characters, so the highlight never splits an Indian-script letter.

### Extra fields in the creator view (`GET /creator/song/get/:id` only)

```json
{
  "chapters": [ { "…": "same as above", "source": "rss" } ],
  "episodeTranscript": {
    "…": "same as above",
    "error": null,
    "options": {
      "asr":       { "status": "ready", "language": "te", "error": null },
      "creator":   { "status": "ready", "language": "te", "enabled": true, "uploadedAt": "2026-11-03T10:00:00.000Z" },
      "publisher": { "status": "ready", "language": "te" }
    }
  }
}
```

An option the episode doesn't have is `null`. The top-level `source`/`url` are always the one users will see, which is `creator` when `options.creator.enabled` is true, otherwise `asr`, otherwise `publisher`.

### Request and response bodies (new endpoints)

Creator endpoints answer with `{ "message": "…", "data": … }`, like the neighbouring `/creator/song/*` endpoints. Admin endpoints use the envelope of the neighbouring `/admin/*` endpoints. Every creator endpoint checks that the song belongs to the caller (403 otherwise), that it is an episode (400 otherwise) and that its audio has been processed, meaning its duration is known (409 otherwise, "Audio is still being processed"). Studio treats 409 as "try again shortly", not as an error.

| Endpoint | Request body | Success response |
| --- | --- | --- |
| `PUT …/chapters` | `{ "chapters": [{ "startMs": 0, "title": "Intro", "linkUrl": null }] }`. `startMs >= 0` and below the episode's duration, `title` 1–120 characters, `linkUrl` an `https` URL or `null`, at most 200 items. | `data: { "chapters": [ …normalized, with id and endMs… ] }`. The server applies the same clean-up rules as for every source, so what the editor previews is what is stored. |
| `DELETE …/chapters` | none | `data: { "chapters": [ …whatever the automatic sources produced… ] }` |
| `POST …/chapters/parse-description` | none | `data: { "chapters": [ …suggestions, nothing saved… ] }`; empty when the description has no valid timestamps |
| `PUT …/speakers` | `{ "speakers": [{ "label": "S1", "name": "Pastor John", "creatorId": null }] }`. `name` at most 80 characters or `null`. Only labels that already exist for the episode are accepted (400 otherwise). | `data: { "speakers": […] }` |
| `POST …/transcript` | `{ "filePath": "<temp key from the existing upload flow>", "language": "te", "format": "vtt" }`. `format` is optional and defaults to the file extension. | `data: { "episodeTranscript": { … } }` |
| `PATCH …/transcript` | `{ "enabled": false }` | `data: { "episodeTranscript": { … } }` |
| `DELETE …/transcript` | none | `data: { "episodeTranscript": { … } }` |

The transcript file for `POST …/transcript` is uploaded first with the existing `POST /creator/upload/generate/presigned` (`uploadType: "transcript"`, `extension: "vtt" | "srt" | "json"`), then PUT to the returned `uploadUrl` with `Content-Type: text/vtt` (vtt), `application/x-subrip` (srt) or `application/json` (json), which are the types Hallelujah Backend signs for those extensions; the returned `filePath` is what the body carries. Files over 5 MB are rejected with 400.

Chapter images and speaker photos are **not** uploaded in this project. A chapter's `imageUrl` comes from the RSS chapters file when it has one. A speaker's `imageUrl` is the linked creator's profile image, or `null`. This keeps the feature out of the image pipeline and its `thumbnail-` key rules.

### Admin endpoints: query and response shapes

Admin responses use the neighbouring `/admin/*` envelope: `{ "data": …, "meta": { "total": n } }` for lists, `{ "data": … }` otherwise.

| Endpoint | Request | `data` |
| --- | --- | --- |
| `GET /admin/episode-transcripts` | Query: `status` (`queued`, `processing`, `ready`, `failed`), `source` (`asr`, `creator`, `publisher`; default `asr`), `songId`, `q` (title contains), `page`, `perPage`. Newest first. | Array of rows (below). |
| `GET /admin/episode-transcripts/usage` | Query: `from`, `to` (`YYYY-MM-DD`, IST days; default last 30 days). | `{ "budgetHoursPerDay": 20, "costPerHourUsd": 0.15, "days": [{ "date": "2026-11-02", "audioHours": 12.4, "costUsd": 1.86, "episodes": 14, "failed": 1 }] }` |
| `POST /admin/episode-transcripts/:songId/queue` | none | `{ "status": "queued" }`. Allowed for `failed` and `none`; 409 while `queued` or `processing`; 429 when today's budget is used up. |
| `PATCH /admin/episode-transcripts/:songId` | `{ "offsetMs": 250 }`, an integer from -60000 to 60000 | The updated row. |

A row:

```json
{
  "songId": "…", "title": "Sunday Sermon", "creator": { "id": "…", "name": "Grace Church" },
  "durationSec": 3600, "source": "asr", "status": "failed", "language": "te",
  "version": 2, "offsetMs": 0, "enabled": true, "provider": "transcribe",
  "attempts": 2, "error": "Language not supported", "audioHours": 1.0, "costUsd": 0.15,
  "createdAt": "2026-11-03T06:00:00.000Z", "updatedAt": "2026-11-03T06:20:00.000Z"
}
```

`error`, `provider` and `attempts` exist only in Admin and creator responses, never in listener responses.

### Contract fixtures

Hallelujah Backend publishes sample files that the other repos copy into their tests, so every client is built against the same bytes:

- `song-detail-episode.json`: an episode with chapters, two speakers and a ready transcript.
- `song-detail-episode-minimal.json`: an episode with none of the new data (`status: none`).
- `song-detail-music.json`: a music song, with none of the new keys.
- `transcript-v2.json`: a small transcript file in the format above, including a Telugu paragraph and a gap longer than 0.7 seconds.
- `creator-song-detail-episode.json`: the creator view.
- `admin-episode-transcripts.json`: a list response with one `ready` and one `failed` row.

## 4. Work breakdown

New `.swift` files need no project edit: `project.yml` uses synced folders for `App`, `Tests` and `UITests`. Run `make generate` only if `project.yml` itself changes.

### Phase 1: Chapters

| Item | Files | Notes |
| --- | --- | --- |
| DTOs | `Data/DTOs/ContentDTOs.swift` (add), `Data/DTOs/EpisodeTimelineDTOs.swift` (new) | `ChapterDTO`, `SpeakerDTO`, `EpisodeTranscriptDTO`, `LenientValue` (I4). Added to `SongDTO` as optional properties. |
| Entities | `Domain/Entities/EpisodeTimeline.swift` (new), `Song.swift` | `EpisodeChapter`, `EpisodeSpeaker`, `EpisodeTranscriptInfo`, `EpisodeTimeline`. `Song.episodeTimeline` with a default (I3); `withFavorited` forwards it. |
| Mapper | `ContentDTOs.swift` `toDomain()` | Map the three fields; apply R2 when building `EpisodeTimeline`; `nil` for music. |
| Shared detail cache | `Data/Repositories/SongDetailCache.swift` (new), `Core/DependencyInjection/AppComposition.swift` | Register next to `SongRepository` (about line 271). Refactor `SongMetaSections.swift` (42) to use it (I2). |
| Timeline store | `Features/Player/State/EpisodeTimelineStore.swift` (new, `@Observable @MainActor`) | Watches `engine.currentSong`; for episodes asks `SongDetailCache`; publishes `EpisodeTimeline?`. Registered in DI. |
| Chapter index | `Features/Player/State/TimelineIndex.swift` (new) | Pure Swift value type, no UI imports. `activeChapter(positionMs:)` by binary search over `chapterStartMs`. |
| Engine accessor | `Platform/Audio/AudioEngine.swift` | `func currentPlaybackMs() -> Int` (I1). One method, covered by a test through the existing fake. |
| Segmented seekbar | `Features/Player/Components/PlayerSeekBar.swift` | `chapters:` parameter (I5). Layout and drag rules in section 5. Light haptic through `HapticFeedback.swift`. |
| Full player wiring | `Features/Player/Views/FullPlayerView.swift` | `nowPlayingControls` (280–301): pass chapters, add the one-line chapter title under the bar. `queueAndShareRow` (396): the Chapters button. Check both `stackedContent` (183) and `sideBySideContent` (219). |
| Chapters sheet | `Features/Player/Components/ChaptersSheet.swift` (new), `.appSheet` | Add its flag to `isPlayerUncovered` (`AppSheet.swift`, 52–56) so the ad clock pauses while it is open. Rows: optional image, title, start, length; current marked; tap seeks and plays. |
| Accessibility | `PlayerSeekBar.swift` | `accessibilityValue` "Chapter 3 of 12, <title>"; `accessibilityAdjustableAction` moves by chapter. Follow `Docs/ACCESSIBILITY.md`. |
| Strings | `App/Resources/Localizable.xcstrings` | Section 6, in all six languages. `Scripts/localization_audit.py` must pass. |
| Tests and previews | `Tests/Data/DTOs/EpisodeTimelineDTOTests.swift`, `Tests/Features/Player/TimelineIndexTests.swift`, fixtures | Section 7. Light and dark previews for the sheet and the bar. |

### Phase 2: Transcript, read-along, speakers

| Item | Files | Notes |
| --- | --- | --- |
| Spike (first, one to two days) | throwaway branch | Build the paragraph view both ways (wrapping layout of word views; `AttributedString` runs) with a real 3-hour transcript on the oldest supported device. Pick one and record it as D21 in `progress.md`. Gate: scrolling stays smooth and the active-word update costs under 2 ms. |
| Transcript repository | `Data/Repositories/TranscriptRepository.swift` (new, actor) | Cache: `DiskCache(directoryName: "transcripts")` with the key `transcript:<songId>:v<version>` (not the URL). Own `URLSession` (I9). On HTTP 403: refresh the song once through `SongDetailCache` (bypassing its TTL), retry with the new URL, then give up quietly. |
| Parsing | `Data/DTOs/TranscriptFileDTO.swift` (new) | Words are `[start, end, text]` arrays, so a custom `init(from:)` over an `UnkeyedDecodingContainer`. Decode in `Task.detached(priority: .utility)` (the repo's existing pattern). Output is flat: `[Int32]` start, `[Int32]` end, `[Int32]` segment, `[String]` words, plus per-segment speaker index. A `format` above 1 gives no transcript. |
| Timeline index | `TimelineIndex.swift` | Add `activeWord(positionMs:)`, `speaker(at:)`. Lookup is `positionMs - offsetMs` (contract). Gap rule: in a gap the active word is the last one that started. |
| Clock | `Features/Player/State/TranscriptClock.swift` (new, `@Observable @MainActor`) | Section 5. Publishes `activeWordIndex`. Starts and stops from `onAppear` / `onDisappear`, `engine.status`, ad-break state and `scenePhase`. Re-arms when `engine.seekGeneration` (44) changes. |
| Read-along card | `Features/Player/Components/ReadAlongCard.swift` (new) | Modelled on `PlayerLyricsPreviewCard` (a 220 pt card with a pill). About three lines around the active word. Tap pushes the transcript route. Placed at the top of `metaSection` (428–452) and gated by R1. |
| Transcript screen | `Features/Player/Views/EpisodeTranscriptView.swift` (new), `Core/Navigation/PlayerRoute.swift`, `Application/AppShellView.swift` (343–355) | A new `PlayerRoute` case and a switch arm, pushed with `coordinator.pushInPlayer`, like `SongLyricsView`. |
| Now speaking chip | `Features/Player/Components/NowSpeakingChip.swift` (new) | Above the read-along card. Two or more speakers only. |
| Speaker names | store | `name` if set, otherwise localized "Speaker N" from the label's position. Avatar from `imageUrl` or initials. |

### Phase 3: Polish

| Item | Files | Notes |
| --- | --- | --- |
| Lock screen and Control Center chapter | `Platform/Audio/NowPlayingCoordinator.swift` (58–70, 74–110) | `trackEngine` deliberately does not observe `currentPosition`. Keep it that way: set `MPNowPlayingInfoPropertyChapterNumber` and `ChapterCount` (and the chapter title) only when the chapter changes, using a one-shot task scheduled for the next chapter boundary, not the position tick. No CarPlay change is needed; it shares the engine. |
| Offline | `TranscriptRepository`, `SongDetailCache` | Persist the timeline JSON (not the signed URL) next to the transcript file so an opened episode keeps its chapters offline. Decision D-I4. |
| Search and share a quote | `EpisodeTranscriptView` | Parent plan Phase 3. |

## 5. Behaviour (same in Hallelujah Flutter)

**Clock (battery).** The parent plan's `TimelineView(.animation(paused:))` redraws every frame while the card or screen is visible. On a screen people leave open for an hour that is the pattern the repo's battery notes warn about. Instead:

- The clock runs only when all are true: `engine.status == .playing`, no ad break, scene is `.active`, and the card or transcript screen is on screen.
- It is **boundary-driven**: read `currentPlaybackMs()` (I1), find the active word, compute the time to the next word's start, and `Task.sleep` until then. On wake, read the position again. A word lasts 250–400 ms, so this is a few wake-ups a second.
- A seek, pause, resume or scene change cancels the task and re-arms it. Under Swift 6 the task is `@MainActor`, and AV callbacks hop to the main actor before touching the clock.
- If the device test shows lag, fall back to `TimelineView(.animation(paused: !isPlaying))` on the transcript screen only (decision D-I3).

**Rendering.** A paragraph is a wrapping layout of word views (iOS 16+ `Layout` protocol), each word a `Text` with its own tap gesture. Paragraph rows are `Equatable` and receive either a state (`.spoken`, `.upcoming`) or the active word index only when they are the active paragraph, so a word change re-renders one row. Words are used exactly as the file gives them, so Indian-script letters are never split.

**Gap rule.** In a gap between words the active word is the last that started. The now-speaking bars pause when the gap is longer than 0.7 s.

**Segmented seekbar.**

- Segment widths are proportional to chapter length with a 3 pt gap. Segments narrower than 6 pt are drawn merged with a neighbour; the data does not change.
- Each segment fills with its played fraction. (No buffered shade on iOS, I6.)
- While dragging: the track grows from 4 pt to 8 pt, a label above the thumb shows the chapter title and time, and a light haptic fires on entering a new chapter. The seek happens on release, as today.
- Under the bar: elapsed time, the current chapter title on one line with "…", and total time.

**Transcript screen.** Lazy list, one paragraph per segment. Speaker header (avatar and name) when the speaker changes, only with two or more speakers. Spoken words full white, current word accent, upcoming words at 38% (I7). Auto-follow keeps the active line about 35% from the top (`SongLyricsView` uses 40%, so use its `scrollTo` anchor pattern with 0.35); user scrolling stops following and shows "Back to current". Tapping a word seeks to its start. "Auto-generated" note when `autoGenerated` is true.

## 6. New strings (all six languages: en, hi, kn, ml, ta, te)

`player.chapters.title`, `player.chapters.xOfY` (with `%1$d` and `%2$d`), `player.readAlong.title`, `player.transcript.title`, `player.transcript.autoGenerated`, `player.transcript.backToCurrent`, `player.speaker.n` (with `%d`), `player.nowSpeaking`. Follow the key naming already used in `Localizable.xcstrings`. No concatenated sentences. Server text is shown as received.

## 7. Not breaking what exists

- **Music is untouched.** `Song.episodeTimeline` is `nil` for music, and every new view returns early without it.
- **Old and new backends both work.** Missing fields decode to nothing (I4). An old app build ignores the new keys.
- **Existing seekbar users render as before.** `PlayerSeekBar`'s default `chapters` is empty. Ad-break and lyrics screens are unchanged.
- **Existing lyrics flow unchanged.** `SongLyricsView`, `PlayerLyricsPreviewCard` and `transcripts` are not edited (R1).
- **Failure is quiet.** A failed download, a 403, an unknown `format` or a bad item gives no transcript UI and no alert. Playback is never affected.
- **No auth headers to the CDN** (I9).
- **No `Song` persistence change.** The timeline is not stored with songs, recents or the queue (I3).
- **Battery.** No task runs when paused, in the background, during an ad, or with the card off screen.

## 8. Verification

```bash
make generate   # only if project.yml changed
make build
make test
make lint
```

`make lint` has 255 violations today and the CI step is non-blocking; new code must add none. New tests (Swift Testing, in `Tests/`):

- `TimelineIndex`: before the first word, inside a word, in a gap, after the last word, exactly on a boundary, with positive and negative `offsetMs`, empty.
- Seekbar segment maths: proportional widths, the 3 pt gap, merging under 6 pt, one chapter, 200 chapters.
- DTO decoding against the five Backend fixtures (placed in `Tests/Support/Fixtures/EpisodeTimeline/`; confirm the synced test folder bundles them), plus bad input: `chapters` as a string, an item missing `startMs`, `format: 2`.
- `Song.withFavorited` keeps `episodeTimeline`.
- The music fixture produces a `nil` timeline.
- `SongDetailCache` coalesces two concurrent requests into one.
- `AudioEngine.currentPlaybackMs()` honours the `pendingSeek` guard.

Manual QA (adds to the parent plan's list): scrub across chapters; seek while playing and check the highlight follows; background and return; airplane mode with a cached transcript; a Telugu paragraph; a 3-hour episode on the oldest supported device; confirm in Instruments that no wake-ups occur when the card is off screen or playback is paused; VoiceOver on the seekbar; iPad split layout (`sideBySideContent`).

## 9. Rollout

1. Fixtures from Hallelujah Backend are copied in; work starts from them without waiting for the server.
2. Phase 1 ships when `episodeChaptersEnabled` is on in staging and the bar has been checked on real data.
3. The Backend switch goes on in production only after this release is live. Until then the fields are absent and the app looks as today.
4. Phase 2 follows the same order with `episodeTranscribeEnabled`.
5. Per the workspace rule, any change made here is checked against Hallelujah Flutter, and the reverse.

## 10. Open decisions (iOS)

| # | Decision | Recommendation |
| --- | --- | --- |
| D-I1 | Word views in a wrapping layout, or `AttributedString` | Decide by the Phase 2 spike. Default to the wrapping layout. |
| D-I2 | Buffered shade on the seekbar | Skip on iOS. It needs new engine code and nothing shows it today. |
| D-I3 | Boundary-driven task or `TimelineView(.animation)` | Boundary-driven; per-frame only on the transcript screen if the device test shows lag. |
| D-I4 | Offline chapters and transcript for downloaded episodes | Cache the timeline when the detail is fetched (Phase 3). Downloads never opened online have none. |
| D-I5 | Clear the transcript cache on sign-out | Yes, via `SessionTeardown`, like the other caches. It is cheap to refetch. |
