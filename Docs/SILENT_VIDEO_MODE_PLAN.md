# Silent video mode: Hallelujah iOS plan and hand-off

Written 2026-11-10. **Status: not started in the app.** This is a plan, written from the finished Hallelujah Flutter build, so a fresh session can implement the same feature in Hallelujah iOS without re-deriving anything. The core Swift (sections 6.2 to 6.5) is already written, and it was compiled and run in a scratch harness on macOS, outside the app; read the verification bullet below before trusting it.

- **Reference implementation** (built and unit-tested, uncommitted on `somesh`, never run on a device; that doc reports 107 tests passing in six files under `/Users/teja/company/projects/projectH/project-h-workspace/app/test/features/podcast/`, which a parallel session wrote and which were not re-run for this file): `/Users/teja/company/projects/projectH/project-h-workspace/app/docs/SILENT_VIDEO_MODE_PROGRESS.md`. Where this file and the Flutter code disagree, Flutter wins (`progress.md` decision D12), except for the platform differences listed in section 6.
- **Why this file is in the Flutter repo:** `app-ios` was on branch `prod` with a clean tree when this was written, and the workspace rule is to edit only on `somesh`. Once `app-ios` is on `somesh`, copy this file to `/Users/teja/company/projects/projectH/project-h-workspace/app-ios/Docs/SILENT_VIDEO_MODE_PLAN.md` (next to `PODCAST_PLAYER_PLAN.md`) and work from the copy.
- **What was verified, and what was not.** The repo's rule applies: work is unverified until it has been built and run.
  - **Compiled and run:** sections 6.2 to 6.5 (`AudioClock`, `VideoSync`, `VideoPlayback`, `AVVideoPlayback`, `PlayerVideoController`) were compiled exactly as shown with `swiftc` 6.3.3 in Swift 6 mode, with `-enable-upcoming-feature ExistentialAny` and `-warnings-as-errors` (zero warnings), against the macOS SDK, with stand-ins for `Song` and `AudioEngine`. A throwaway harness then ran **179 checks, all passing**: the planner against every case of `video_sync_test.dart`, 13 controller scenarios against fakes, `AVVideoPlayback` against a local 40 second silent mp4, and an end-to-end loop with a fake clock that follows real time. Each fenced block in 6.2 to 6.5 is one file, so paste it rather than retyping it.
  - **Type-checked only:** section 6.6 (the SwiftUI layer), with a stand-in for the surface. Everything from 6.7 on is design.
  - **Measured separately, on macOS (not iOS):** how `AVPlayer` sends custom headers through the proxy's 302 redirect, against local HTTP servers (section 6.9), and which containers and codec tags `AVVideoPlayback` can open (risk R1 and section 8.3).
  - **Not checked:** the iOS SDK; the app project and its build settings; SwiftLint (it was not installed, so nothing was linted); a simulator or device; the real `AudioEngine`; HTTPS; the real backend.
  - The harness was a throwaway and is not kept. Section 8 lists what it checked, and the Swift Testing tests are still to be written.

| Name | Path |
| --- | --- |
| Hallelujah Flutter (`app`) | `/Users/teja/company/projects/projectH/project-h-workspace/app` |
| Hallelujah iOS (`app-ios`) | `/Users/teja/company/projects/projectH/project-h-workspace/app-ios` |
| Hallelujah Backend (`backend`) | `/Users/teja/company/projects/projectH/project-h-workspace/backend` |

iOS paths below that do not start with `/` are relative to the Hallelujah iOS repo root.

---

## Start here (new session)

1. Run `git -C /Users/teja/company/projects/projectH/project-h-workspace/app-ios branch --show-current`. It must print `somesh`. On 2026-11-10 it printed `prod`. If it is not `somesh`, **stop and tell the user**; do not switch branches, merge or stash unless they ask. The work branch is created from `main`, and `main` is merged into `somesh` before new work.
2. Run `git status` before touching anything; these repos often carry uncommitted work.
3. Read, in this order: this file; `progress.md` (decisions D3, D6, D7, D8, D12, D13, D20, D22, D25 and the non-negotiables; the last decision is D25); `Docs/PODCAST_PLAYER_PLAN.md`; `Docs/ACCESSIBILITY.md`; `Docs/PERFORMANCE.md`; the Flutter doc sections 4 and 5; then the Flutter sources in section 4 below; then the Flutter tests in `/Users/teja/company/projects/projectH/project-h-workspace/app/test/features/podcast/`, starting with `video_sync_test.dart` (section 8).
4. Use the code-review-graph MCP tools before Grep, Glob or Read (workspace rule). The graph was empty (0 nodes) when this was written; if it still is, run `build_or_update_graph_tool` with the iOS repo root, or fall back to grep.
5. Follow the steps in section 7 in order. Each one builds and tests on its own.
6. Do not commit or push unless the user asks. Scratch files go in the session scratchpad, never in a repo or in `project-h-workspace/`.

---

## 1. The request

The user asked for this on the Flutter app (verbatim, with a player screenshot):

> in our flutter app audio player page , somewhere in this page at proper location i need swich to video / swich to audo toggles, at proper location as spotify does, and in our song schema there is videoFile @app/lib/views/home/audio_player_screen.dart , so this videoFile column should be utlized which will be silent video no sounds so our podcasts player (audio handler) should not stop or pause only video should be resumed at audio current position and both should be in sync, if user swich to audio mode then video player should be disposed but audio will not break

Then: "also i need md file for same work ios native". This file is that.

What it means on iOS:

| # | Requirement |
| --- | --- |
| R1 | A "Switch to video" / "Switch to audio" control on the full player, on the artwork, where Spotify puts it. |
| R2 | It plays `Song.videoFile`, which is a silent video. |
| R3 | The audio engine never stops or pauses because of it. Only the video starts or resumes at the audio's current position, and it stays in sync. |
| R4 | Switching back to audio disposes the video player. The audio is not interrupted. |
| R5 | Only an episode that has a video shows the control. Everything else on the player looks exactly as it did. |

---

## 2. Status

| Piece | Hallelujah Flutter | Hallelujah iOS |
| --- | --- | --- |
| Backend (`Song.videoFile` produced as a silent video) | done, see `/Users/teja/company/projects/projectH/project-h-workspace/backend/docs/features/episode-video-audio-split.md` | same backend, nothing to do |
| Data model (`videoFile`) | already in the Realm `Song`; `hasVideo` added | not started |
| Sync policy (pure, testable) | built | `AudioClock` and `VideoSync` written (6.2, 6.3), compiled and run on macOS; not in the app |
| Video layer and controller | built | controller and `AVPlayer` wrapper written (6.4, 6.5) and checked the same way; the SwiftUI layer (6.6) type-checked only; none of it in the app |
| Toggle, mode state, placement | built | not started |
| Strings (6 languages) | done | not started |
| Unit and widget tests for the feature | written (107 reported passing; not re-run for this file) | not written; the planner, controller and `AVPlayer` wrapper were checked in a macOS scratch harness (section 8) |
| Run on a device or simulator | **never** | never |
| Committed | no (uncommitted on `somesh` in `app`) | nothing exists |

---

## 3. The contract Flutter implements (reproduce this)

### 3.1 Behaviour

1. **Who gets a pill.** `Song.hasVideo` is `(videoFile ?? '').trim().isNotEmpty`. It is not gated on `type`. When it is false the control is an empty view and the player is exactly what it was.
2. **What the pill says.** It names what a tap will do: "Switch to video" on the cover, "Switch to audio" over the picture. The glyph is the destination's (camera when going to video, headphones when going to audio). One line, ellipsised if it must be.
3. **Where it sits.** On the artwork, bottom trailing corner, a small floating pill. The pill is centred in a tap box of at least 48 x 48 pt, and it is the box that sits 4 pt in from the trailing edge and 2 pt up from the bottom (Flutter's `Positioned` offsets apply to the box, not to the visible pill). It sits **inside the ad overlay's content**, so an ad takeover covers the whole artwork, pill included. There is never a control on top of an ad.
4. **Mode is the listener's choice, not a fact about one song.** It is one app-wide boolean. Switch to video and the next episode that has a video opens as video too. An episode with no video shows its cover and no pill, and the choice waits for the next one that has one. It is held for the life of the app and **not persisted**: a fresh launch starts on the cover.
5. **Where the picture is drawn.** Over the cover, inside the artwork pager, and only on the page whose song is the one currently playing. Swiping the pager to a neighbouring song shows that song's cover, never a video.
6. **Opening.** The video player is created, muted (`volume 0`) before anything else, then initialised. Nothing is painted (opacity 0) until the picture is the right frame.
7. **Sync loop.** Every 250 ms: read the video position, then the audio clock straight after (so the two readings are close in time), plan, update "shown", then apply the plan **without waiting** for seek/play/pause to finish. (Flutter's video read is asynchronous, so it reads the video first and the audio straight after. On iOS both reads are synchronous inside one main-actor turn, so the order does not matter and the Swift reads the audio first, section 6.5.)
8. **Reveal and hide.** Reveal only when the video is in step and not buffering. Hide only after the drift has stayed above 1.5 s for at least 1 s. A skip or a scrub must not flash the cover.
9. **Fade.** Opacity animates over 220 ms, ease-out.
10. **Fit.** Cover (fill and crop) when the video's aspect is within 6 percent of the box's aspect; otherwise contain (letterbox). Background behind the picture is the dark token.
11. **The picture is decoration.** It takes no taps, and is hidden from accessibility.
12. **Release.** The video player is released when: the user switches to audio; the song changes; the ad break replaces the player; the player screen is left; the app goes to the background; a **full page** is pushed over the player. Sheets over the player do **not** release it in Flutter. A brief `inactive` state (permission prompt, notification shade) does not release it either.
13. **Failure.** On the first hard failure the player is released, mode returns to the cover, the toast "Video isn't available right now" is shown, and the audio carries on. It is reported once. Opening the video again later retries from scratch.
14. **Audio is never driven.** The only handle the video code has on the audio is a read-only clock (section 6.2).

### 3.2 The numbers

| Constant | Value | Meaning |
| --- | --- | --- |
| Playing tolerance | 300 ms | Drift allowed while both are running. |
| Paused tolerance | 120 ms | Tighter, because a paused listener scrubbing expects the exact frame. |
| Playing seek cooldown | 1500 ms | Least time between two corrective seeks while playing. |
| Paused seek cooldown | 250 ms | Short, so a scrub keeps the frame up with the thumb. |
| Tail guard | 150 ms | Within this of the video's end, stop asking it to play. |
| Seek lead | 200 ms | A corrective seek while playing lands this far ahead of the audio. |
| Hide drift | 1500 ms | Drift past which a shown picture is wrong. |
| Hide grace | 1000 ms | How long the drift must stay past the hide drift before the cover returns. |
| Fill tolerance | 0.06 | Cover versus contain. |
| Reconcile interval | 250 ms | Sync loop period. |
| Crossfade | 220 ms | Reveal and hide animation. |

Landing rule: while playing, a corrective seek lands at `audio position + 200 ms`, clamped to `duration - 150 ms`. While paused it lands exactly on the audio position. The drift check is strict (`>`).

### 3.3 Decisions and why (do not "improve" these in the port)

| Decision | Why |
| --- | --- |
| The audio is the clock, the video only follows, and that only goes one way. | The whole point of a silent video beside a podcast is that a late, stalled or failed video costs a frame, never a word. |
| `AudioClock` is read-only: four reads, no methods. | The guarantee is held by the type, not by anyone's care. Code with an `AudioClock` cannot touch the audio even by mistake. |
| The audio is read fresh on every call; nothing is cached. | Flutter's handler replaces its player after errors; a cached reference reads a dead one. Do the same on iOS with the engine. |
| The policy is a pure function with hysteresis (tolerance, cooldown, hide grace). | Every rule is a plain unit test rather than something to watch happen on a phone. |
| Seek lead of 200 ms. | A seek takes a moment to land and the audio does not wait. Aiming ahead turns that lag into a small lead inside the tolerance on either side. |
| Cooldown after a seek. | A seek makes the player rebuffer and report a position nowhere near its target. Correcting again in that moment turns one slip into a stutter that never settles. |
| No seek while playing and buffering. | A seek during a rebuffer restarts the rebuffer. |
| Tail guard. | Flutter's plugin restarts a finished video on `play()`. Keep the guard on iOS too, it costs nothing. |
| A video shorter than the audio holds its last frame (target is clamped to the duration). | Covers a slightly shorter silent copy. |
| Cooldowns and grace measured on the loop's own virtual elapsed time (sum of 250 ms ticks), not the wall clock. | Deterministic in tests. |
| Seek, play and pause are fire-and-watch (not awaited), guarded by a generation counter (on iOS, `.task` cancellation does that job, section 6.6). | A slow seek must never hold up the next check; a release can land in the middle of an await. |
| No `AVPlayer.masterClock` or `setRate(_:time:atHostTime:)` coupling to the audio player. | It would require commanding the audio player. Rejected on purpose. |

---

## 4. Flutter to iOS file map

Flutter paths are absolute; iOS targets are relative to the iOS repo root. `App` and `Tests` are `syncedFolder`s in `project.yml`, so new files are picked up without running XcodeGen (run `make generate` anyway if the project looks stale).

| Flutter source | What it holds | iOS target |
| --- | --- | --- |
| `/Users/teja/company/projects/projectH/project-h-workspace/app/lib/features/podcast/state/video_sync.dart` | Constants, `planVideoSync`, `videoDrift`, `nextVideoShown`, `videoFitFor` | `App/Features/Player/State/VideoSync.swift` (code in 6.3) |
| `.../app/lib/features/podcast/state/audio_clock.dart` | Read-only `AudioClock` + `HandlerAudioClock` | `App/Features/Player/State/AudioClock.swift` (protocol + `EngineAudioClock`; code in 6.2) |
| `.../app/lib/features/podcast/providers/player_video_mode_provider.dart` | App-wide `bool`, `showVideo/showCover/toggle` | `App/Features/Player/State/PlayerVideoModeStore.swift` (`@MainActor @Observable`) |
| `.../app/lib/features/podcast/widgets/media_mode_toggle.dart` | The pill | `App/Features/Player/Components/MediaModeToggle.swift` |
| `.../app/lib/features/podcast/widgets/player_video_slot.dart` | Decides whether a page shows video; builds the source; handles unavailable | `App/Features/Player/Components/PlayerVideoSlot.swift` |
| `.../app/lib/features/podcast/widgets/player_video_layer.dart` | Player lifetime, sync loop, shown flag, failure, surface | `App/Features/Player/Components/PlayerVideoLayer.swift` (6.6) + `State/PlayerVideoController.swift` (6.5) + `State/VideoPlayback.swift` (the protocol only, 6.4) + `App/Platform/Video/AVVideoPlayback.swift` (6.4; a new folder, because `AVPlayer` owners live under `App/Platform/`) + a shared `VideoSurface` (see step 6) |
| `.../app/lib/models/song.dart` (`hasVideo`, line 86) | `videoFile` check | `Song.videoFile` + `Song.hasVideo` in `App/Domain/Entities/Song.swift` |
| `.../app/lib/theme/colors.dart` (`artworkControlBackground = Color(0x8C000000)`) | Pill background | `PlayerStyle.artworkControlBackground` in `App/Features/Player/Components/PlayerStyle.swift` |
| `.../app/lib/views/home/audio_player_screen.dart` (`_ArtworkWithModeToggle`) | Places the pill over the pager, inside the ad overlay's child | `FullPlayerView.artwork(width:)` |
| `.../app/lib/widgets/player/player_artwork_pager.dart` (`_Artwork` Stack) | Puts `PlayerVideoSlot` over each cover | `PlayerArtworkPager` per-song page |
| `.../app/lib/l10n/app_{en,hi,kn,ml,ta,te}.arb` keys `playerSwitchToVideo`, `playerSwitchToAudio`, `playerVideoUnavailable` | Strings | `App/Resources/Localizable.xcstrings` (section 6.12) |

---

## 5. iOS facts (read on 2026-11-10; line numbers are approximate, re-find by symbol)

| File | Fact |
| --- | --- |
| `App/Features/Player/Views/FullPlayerView.swift` | Has `@Environment(\.toastCenter) toastCenter` (~line 25) and `@Environment(\.scenePhase) scenePhase` (~26). Dependencies are `@State` values resolved with `DependencyContainer.current.resolve()` (engine, timelineStore, queueController, adPacing, playerAd...). `isPlayerUncovered` (~56-60) is `coordinator.playerPath.isEmpty && !isSharePresented && !isQueuePresented && !isAddToPlaylistPresented && !isSleepTimerSheetPresented && !isTipSheetPresented && menuSong == nil`. `.onChange(of: scenePhase)` at ~160. `artwork(width:)` (~294-302) is `PlayerAdOverlay(controller: playerAd, onOpen: ..., isUncovered: isPlayerUncovered) { PlayerArtworkPager(queueController: queueController, width: width) }`, used by both `stackedContent` and `sideBySideContent`. `song` is `engine.currentSong`. The body swaps to `AdBreakView` while `adPacing.isAdBreak`. |
| `App/Features/Player/Components/PlayerArtworkPager.swift` | `TabView(selection:)` in `.page` style. Per song: `GeometryReader { proxy in ArtworkView(url:width:height:cornerRadius:) }.tag(song.id)`. Uses `PagerFrame` and `.simultaneousGesture(edgeOverscrollGesture)`. Existing test: `Tests/Features/Player/PlayerArtworkPagerTests.swift`. |
| `App/Features/Player/Ads/PlayerAdOverlay.swift` | Simultaneous tap (opens the ad) and drag (dismisses it); overlay is `PlayerAdCard` with a 0.35 s fade. |
| `App/Features/Player/Views/AdBreakView.swift` (~198-235) | `private struct ReelVideoSurface: UIViewRepresentable` and `private final class PlayerLayerView: UIView` (an `AVPlayerLayer`, black background, `.resizeAspect`, frame set in `layoutSubviews` inside a `CATransaction` with actions disabled). **Extract this, do not copy it**, and give it a gravity parameter. |
| `App/Platform/Ads/AdPacingController.swift` (~278) | Shows the house pattern for an `AVPlayer` with `@Sendable` KVO and a generation counter. The port deliberately polls instead of using KVO (section 6.4). |
| `App/Platform/Audio/AudioEngine.swift` | `@MainActor @Observable final class AudioEngine`. `Status { idle, loading, playing, paused, failed(String) }` (use `if case` / `switch`; it may not be `Equatable`). `currentSong`, `currentPosition` (0.5 s ticks) and a **private** `AVQueuePlayer`. **`func currentPlaybackMs() -> Int`** (~356-363) is the precise, on-demand playhead and is the source for `AudioClock.positionMs`. `makePlayerItem` (~777-807) builds `AVURLAsset(url:options:)` with `options["AVURLAssetHTTPHeaderFieldsKey"] = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]`, where the token is `await tokenProvider.validAccessToken() ?? ""`. |
| `App/Platform/Audio/AudioSourceResolver.swift` (144 lines) | `struct AudioSourceResolver: Sendable` with `private let proxyBaseURL`. `private static func proxyURL(for key:base:)` (~138-143) percent-encodes the key (urlQueryAllowed minus `&=+`) and returns `URL(string: base.absoluteString + "/proxy?path=\(encodedKey)")`. Add the video method in this same file so it can reuse that helper. |
| `App/Domain/Entities/Song.swift` | No `videoFile`. The last stored property is `var episodeTimeline: EpisodeTimeline? = nil` (~124). **`withFavorited(_:)` (~155-205) rebuilds the whole `Song(...)` and silently drops any property it does not list.** |
| `App/Data/DTOs/ContentDTOs.swift` | `SongDTO: Decodable, Sendable` (~216) ends with lenient `chapters`, `speakers`, `episodeTranscript`. `toDomain()` (~294+) builds `Song(...)` using `sanitized(...)` for strings. |
| `Song(` construction sites in `App/` | `App/Data/DTOs/ContentDTOs.swift:295` (must pass `videoFile`), `App/Domain/Entities/Song.swift:156` (`withFavorited`, must copy it), `App/Core/Persistence/RecentSearchStore.swift:54` and `App/Platform/CarPlay/CarPlayContentProvider.swift:348` (rebuild a `Song` without video; fine, but see risk R12). |
| `App/Core/DependencyInjection/AppComposition.swift` | The engine is built at ~363-370 (`AudioEngine(proxyBaseURL:keyValueStore:batteryMonitor:connectivityType:tokenProvider:session)`). Podcast player shared instances are registered right after it (~371-383), e.g. `container.register(EpisodeTimelineStore.self) { episodeTimelineStore }`. Register the mode store there. |
| `App/Core/Networking/Interceptors/AuthTokenProviding.swift` | `validAccessToken() async -> String?`. Non-throwing; refreshes if expired or inside the last 2 minutes. Its doc comment names AVPlayer among the callers that cannot replay a request after a 401, which is why the token is fetched up front (section 6.9). |
| `App/Features/Player/State/` | Holds `DescriptionTimestamps.swift`, `EpisodeTimelineStore.swift`, `TimelineIndex.swift`, `TranscriptClock.swift`. Pure logic goes here. `ViewModels/` is empty. |
| `App/Features/Player/Components/` | `PlayerStyle.swift`, `PlayerArtworkPager.swift`, `NowSpeakingChip.swift`... |
| `App/Features/Ads/AdSponsoredBadge.swift` | The closest existing on-artwork chip: inline `Color.black.opacity(0x8C / 255)`, `Dimens.spacing6` / `spacing2`, `Dimens.cornerRadiusSmall`, white text. Reuse the look, **not** the inline literal. |
| `App/DesignSystem/Tokens/IconToken.swift` | `enum IconToken: CaseIterable, Sendable`. Its header comment says the vocabulary grows per feature. `systemName` is a `switch` with no `default`, so every new case needs an entry there (the compiler points at a missing one); `assetName` is for Flutter's brand SVGs and ends in `default: nil`, which is right for a token where Flutter draws a Material icon, as it does here. Checked 2026-11-10: there is no video or headphones case. Add `.video` (`video.fill`) and `.headphones` (`headphones`). |
| `App/DesignSystem/Tokens/Dimens.swift` and the Spacing / Radius / MotionDuration / Typography tokens | `Spacing` (xs 4, sm 8, md 16, lg 24, xl 32, xxl 48, `minTapTarget` 48). `Dimens` (`spacing2/4/6/8/12/16`, `iconSize` 24, `iconSizeSmall` 16). `MotionDuration` (fast 0.15, normal 0.3, slow 0.45; there is no 0.22, add a token). `Typography.labelMedium` applied with `.typography(...)`. |
| `GlassSurface` | `GlassSurface(_ variant:in:interactive:)` with Capsule and RoundedRectangle conveniences; variants `.regular`, `.clear`, `.tinted(ColorToken)`. |
| `Makefile` | `bootstrap`, `generate`, `lint` (swiftlint --strict + swiftformat --lint), `format-fix`, `test` (`-only-testing:HallelujahTests`, scheme "Hallelujah Development", iPhone 17 Pro simulator), `build`, `clean`. |
| Tests | Swift Testing. `Tests/Support/Fixtures/SongFixture.swift` builds test songs. Tests live in `Tests/Features/Player/`, `Tests/Core/...`. |
| `Config/Shared/Base.xcconfig` | `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`. The Swift in section 6 was compiled with the first three. |
| `.swiftlint.yml`, `.swiftformat` | SwiftLint: `identifier_name` minimum length 2, `line_length` 120 warning and 160 error, the default `function_parameter_count` of 5, run with `--strict`. SwiftFormat: Swift 6.0, indent 4, max width 120, `--self remove`, `--importgrouping testable-bottom`. Neither tool was installed where the Swift was checked, so nothing was linted (the only check made is that no line is longer than 120 characters). Step 10 is the first lint. |

Backend facts the video depends on (so you do not have to re-read the backend):

- `videoFile` is meaningful for `Song.type == "episode"` only. A video-only upload makes `song.process` set `audioFile` to an mp3 and `videoFile` to the **stream-copied silent video** at `<prefix>/video-song/<assetId>-silent/original.<ext>`. If a creator supplies both files nothing is split and the video is kept as uploaded, so it **may have sound**. That is why the video is always muted. (`/Users/teja/company/projects/projectH/project-h-workspace/backend/docs/features/episode-video-audio-split.md`)
- The split keeps the upload's extension and codec. Allowed upload extensions are `mp4|mov|avi|mkv|webm` (`.../backend/src/validations/creator/song.validation.js:103` and `:285`). `-movflags +faststart` is applied for `mp4` and `mov` only (`.../backend/src/jobs/song/videoAudioSplit.js:173`). See risk R1: on macOS, AVFoundation did not open `webm` or `mkv`, and opened `avi` and HEVC only for some codecs and tags.
- Media is fetched through the proxy, `GET /api/proxy?path=<key>` (auth required: `authMiddleware` guards `/api/proxy`, `/creator/proxy` and `/admin/proxy` at `.../backend/src/proxy/app.js:53-56`, and the route is at `:71`, with the same handler mounted at `/creator/proxy` and `/admin/proxy` on lines 72-73. The proxy is also rate limited per IP: `PROXY_RATE_LIMIT` requests, default 200, per 15 minutes, at `:39-40`). The handler answers **302** to a CloudFront-signed URL (when `USE_CLOUD_FRONT=true`) or an S3 presigned URL, valid 3 hours by default, cached in Redis, with `Cache-Control: private, max-age=<0.9 x expiry>` (`.../backend/src/controllers/common/proxy.controller.js:61-86`). Byte ranges are therefore served by CloudFront or S3, not by Node.
- Whether `videoFile` is present in the JSON the feeds return has **not been verified** on a real episode. Check it first (step 1).

---

## 6. iOS design

### 6.1 Protecting the audio (R3, R4)

The audio engine's `AVQueuePlayer` is private to `AudioEngine`. Keep it that way: the video code gets a read-only `AudioClock` and nothing else.

- The new video files must not mention `AudioEngine` except `AudioClock.swift` (`EngineAudioClock`). Check with `grep -rn AudioEngine` over the new files.
- The new video files must not touch `AVAudioSession` at all (no `setCategory`, no `setActive`). Check with `grep -rn AVAudioSession`. A second `AVPlayer` in the same app shares the existing session, and a muted one is expected not to interrupt the engine (not proven on iOS; device checks 2 and 7 prove it). That is why iOS should need no equivalent of Android's `mixWithOthers` option, and why Flutter passes no options on iOS either.
- The video player is muted twice: `player.isMuted = true` and `player.volume = 0`, set in `AVVideoPlayback.init` before the first `play()` (section 6.4).
- Do not edit `AudioEngine` for this feature. Reuse `currentPlaybackMs()` as it is.

### 6.2 `AudioClock`

Sections 6.2 to 6.5 hold Swift files exactly as they were compiled and run in the harness described at the top of this file. **Each fenced block is one file: paste it, do not retype it.** The only edits to expect are at the places where a file meets the real app (the names `AudioEngine` and `Song`, and the iOS SDK); each section says where.

`App/Features/Player/State/AudioClock.swift`:

```swift
/// What the silent video may know about the audio, and by the shape of this type nothing more:
/// four reads and no methods. Code holding an `AudioClock` cannot stop, pause, seek or wait for the
/// audio, even by mistake.
@MainActor
protocol AudioClock {
    /// Where the audio is now. Meaningful only while `isReady` and `mediaId` is the episode being
    /// looked at.
    var positionMs: Int { get }
    /// Whether the listener has the audio playing, as opposed to paused.
    var isPlaying: Bool { get }
    /// Whether the audio is producing sound at `positionMs`. False while loading, rebuffering,
    /// finished or idle, when the position says nothing about what is heard.
    var isReady: Bool { get }
    /// The id of the item the audio has loaded: an episode's `Song.id`.
    var mediaId: String? { get }
}

/// The real clock. It reads the engine fresh on every call and caches nothing.
@MainActor
struct EngineAudioClock: AudioClock {
    let engine: AudioEngine

    var positionMs: Int { engine.currentPlaybackMs() }

    var isPlaying: Bool {
        if case .playing = engine.status { true } else { false }
    }

    var isReady: Bool {
        switch engine.status {
        case .playing, .paused: true
        case .idle, .loading, .failed: false
        }
    }

    var mediaId: String? { engine.currentSong?.id }
}
```

- **This is the only new file that names `AudioEngine`.** `EngineAudioClock` is the one place the video feature touches the engine, and what it touches is four reads (section 6.1).
- **The `switch` has no `default`, on purpose.** If `AudioEngine.Status` gains a case, the compiler stops here and somebody decides whether that case counts as ready. When you paste this file, check its cases against the real `AudioEngine.Status` (`idle`, `loading`, `playing`, `paused`, `failed(String)` when this was written) and keep the `switch` exhaustive.
- **What the flags mean.** `isPlaying` is the listener's intent: the engine is in `.playing` (Flutter: `player.playing`). `isReady` is true only in `.playing` or `.paused`, that is, when `positionMs` says where the sound is (Flutter: `processingState == ready`). `mediaId` is the engine's `currentSong?.id`; the controller compares it with its own song id, so audio that has moved on to another episode counts as not ready and the video simply waits.
- **Nothing is cached.** Every read goes to the engine, so nothing can go stale if the engine rebuilds its player (Flutter's handler replaces its `just_audio` player after errors, which is why it works the same way).
- **What a mid-playback stall looks like to this type is not known (risk R16).** Check how `AudioEngine.status` behaves when the audio stalls: does it flip to `.loading`, or stay `.playing` while the `AVQueuePlayer` waits? If it stays `.playing`, the position stops advancing while the video runs on, and the planner will pull the video back with a few jumps. That is harmless, so do not change the engine for it; just record what you saw.

### 6.3 The planner (pure, no AVFoundation)

`App/Features/Player/State/VideoSync.swift`. It mirrors `/Users/teja/company/projects/projectH/project-h-workspace/app/lib/features/podcast/state/video_sync.dart` case for case. The Dart `planVideoSync` takes eight named parameters; SwiftLint's `function_parameter_count` warns above five and `--strict` turns warnings into errors, so the Swift takes two small reading structs (`AudioReading`, `VideoReading`) plus `sinceLastSeekMs`. The names are suggestions; grep for clashes before pasting.

```swift
import Foundation

/// What the planner knows about the audio. The audio is the clock; nothing in this file can
/// command it.
struct AudioReading: Sendable, Equatable {
    var positionMs: Int
    /// False while the audio is loading, rebuffering or finished: its position says nothing then.
    var isReady: Bool
    /// The listener's intent: playing, as opposed to paused.
    var isPlaying: Bool
}

/// What the planner knows about the silent video.
struct VideoReading: Sendable, Equatable {
    var positionMs: Int
    /// Zero while unknown.
    var durationMs: Int
    var isPlaying: Bool
    var isBuffering: Bool
}

/// What the video has to do to stay with the audio.
struct VideoSyncPlan: Sendable, Equatable {
    /// Where to jump the video to. `nil` leaves its position alone.
    var seekToMs: Int?
    /// `true` to play it, `false` to pause it, `nil` to leave it as it is.
    var play: Bool?

    var isNoop: Bool { seekToMs == nil && play == nil }
}

enum VideoFit: Sendable, Equatable {
    case cover
    case contain
}

/// Decides what the silent video does to follow the audio.
///
/// THE AUDIO IS THE CLOCK AND THE VIDEO IS THE FOLLOWER, and that only ever goes one way. Nothing
/// here, and nothing that carries out a plan, can stop, pause, seek or wait for the audio: a video
/// that is late, stalled or failed costs a frame, never a word.
///
/// Pure on purpose: the caller feeds it what it just read from the two players and does what comes
/// back, so every rule is a plain unit test rather than something to watch happen on a phone.
enum VideoSync {
    /// Drift allowed while both are running before the video is pulled back.
    static let playingToleranceMs = 300
    /// The same while the audio is paused: the picture is a still, so it is held closer.
    static let pausedToleranceMs = 120
    /// Least time between two corrective jumps while playing. A jump makes the player rebuffer and
    /// report a position nowhere near its target; correcting again then turns one slip into a stutter.
    static let playingSeekCooldownMs = 1_500
    /// Least time between two jumps while paused: short, so a scrub keeps the frame up with the thumb.
    static let pausedSeekCooldownMs = 250
    /// Within this of the video's end the video is no longer asked to play.
    static let tailGuardMs = 150
    /// A corrective jump while playing lands this far ahead of the audio, because it takes a moment
    /// to land and the audio does not wait. Must stay below `playingToleranceMs`.
    static let seekLeadMs = 200
    /// Drift past which a picture that is showing no longer belongs to what is heard.
    static let hideDriftMs = 1_500
    /// How long the drift must stay past `hideDriftMs` before the cover returns.
    static let hideGraceMs = 1_000
    /// How close a video's aspect must be to the box's before the video fills the box.
    static let fillTolerance = 0.06
    /// Period of the sync loop.
    static let reconcileIntervalMs = 250

    /// What the video has to do right now to stay with the audio. `sinceLastSeekMs` is how long ago
    /// the video was last jumped, `nil` if never.
    static func plan(audio: AudioReading, video: VideoReading, sinceLastSeekMs: Int?) -> VideoSyncPlan {
        guard audio.isReady else {
            return VideoSyncPlan(seekToMs: nil, play: video.isPlaying ? false : nil)
        }
        let target = targetMs(audio: audio, video: video)
        let playing = wantsPlaying(audio: audio, video: video)
        let cooldown = playing ? playingSeekCooldownMs : pausedSeekCooldownMs
        let cooledDown = sinceLastSeekMs.map { $0 >= cooldown } ?? true
        let drifted = abs(video.positionMs - target) > tolerance(playing: playing)
        // A jump while the player is rebuffering restarts the rebuffer.
        let seeks = drifted && cooledDown && !(playing && video.isBuffering)
        return VideoSyncPlan(
            seekToMs: seeks ? landingMs(target: target, playing: playing, video: video) : nil,
            play: playDecision(playing: playing, video: video)
        )
    }

    /// How far the video is from where it should be, in either direction.
    static func drift(audio: AudioReading, video: VideoReading) -> Int {
        abs(video.positionMs - targetMs(audio: audio, video: video))
    }

    /// Whether the picture is on screen over the cover. It comes up only once it is the right frame
    /// (in step and not buffering) and stays until it has been wrong for a while, so a skip or a
    /// scrub does not flash the cover. `outOfSyncForMs` is how long the drift has been past
    /// `hideDriftMs`, zero when it is not.
    static func nextShown(shown: Bool, audio: AudioReading, video: VideoReading, outOfSyncForMs: Int) -> Bool {
        guard audio.isReady else { return shown }
        let off = drift(audio: audio, video: video)
        if shown {
            return !(off > hideDriftMs && outOfSyncForMs >= hideGraceMs)
        }
        let playing = wantsPlaying(audio: audio, video: video)
        return !video.isBuffering && off <= tolerance(playing: playing)
    }

    /// Fill the box when the video is the box's shape to within a few percent, fit it otherwise.
    static func fit(videoAspect: Double, boxAspect: Double) -> VideoFit {
        guard videoAspect > 0, boxAspect > 0 else { return .contain }
        return abs(videoAspect / boxAspect - 1) <= fillTolerance ? .cover : .contain
    }

    // MARK: - Pieces

    /// Where the video should be for the audio to be at `audio.positionMs`: the same place, except
    /// that a video shorter than the audio holds on its last frame.
    private static func targetMs(audio: AudioReading, video: VideoReading) -> Int {
        video.durationMs > 0 && audio.positionMs > video.durationMs ? video.durationMs : audio.positionMs
    }

    /// Within the tail guard of the video's end. A video whose length is not known yet cannot be run
    /// off the end of, so it is never near it.
    private static func isNearEnd(audio: AudioReading, video: VideoReading) -> Bool {
        video.durationMs > 0 && audio.positionMs >= video.durationMs - tailGuardMs
    }

    /// Whether the video should be playing: the audio is, and the video has not run out.
    private static func wantsPlaying(audio: AudioReading, video: VideoReading) -> Bool {
        audio.isPlaying && !isNearEnd(audio: audio, video: video)
    }

    private static func tolerance(playing: Bool) -> Int {
        playing ? playingToleranceMs : pausedToleranceMs
    }

    /// Where a corrective jump lands: a little ahead of the audio while it runs, never past the point
    /// where playing would restart the video, and exactly on the audio while it is paused.
    private static func landingMs(target: Int, playing: Bool, video: VideoReading) -> Int {
        guard playing else { return target }
        let ahead = target + seekLeadMs
        return video.durationMs > 0 ? min(ahead, video.durationMs - tailGuardMs) : ahead
    }

    /// A buffering video has been told to play already, so it is not told again.
    private static func playDecision(playing: Bool, video: VideoReading) -> Bool? {
        if playing && !video.isPlaying && !video.isBuffering { return true }
        if !playing && video.isPlaying { return false }
        return nil
    }
}
```

What each function decides:

- `plan(audio:video:sinceLastSeekMs:)`: what to do to the video right now. A jump (`seekToMs`), a play or a pause (`play`), both, or nothing (`isNoop`).
- `nextShown(shown:audio:video:outOfSyncForMs:)`: whether the picture may be on screen over the cover. It comes up only when the video is in step and not buffering, and it goes only after the drift has stayed above `hideDriftMs` for at least `hideGraceMs`. The caller keeps the out-of-sync stopwatch (`outOfSyncForMs`).
- `drift(audio:video:)`: how far the video is from where it should be (the target is clamped to a shorter video's end).
- `fit(videoAspect:boxAspect:)`: cover when the two aspects are within `fillTolerance` (6 percent) of each other, otherwise contain. An unknown (zero or negative) aspect is contain.

Details that are easy to get wrong:

- **The drift check is strict (`>`).** Exactly 300 ms off while playing is still in step; 301 is not. Exactly 120 ms off while paused is still in step; 121 is not.
- **Landing.** While playing, a jump lands 200 ms ahead of the audio (`seekLeadMs`), clamped to the video's duration minus 150 ms (`tailGuardMs`). While paused it lands exactly on the audio position.
- **The end of the video.** Within 150 ms of the end the video is not asked to play and the paused tolerance applies. A video shorter than the audio holds its last frame (the target is clamped to the duration). An unknown duration (0) is never "near the end".
- **Audio not ready.** The plan never jumps, and pauses a video that is playing; `nextShown` returns whatever it was given.

### 6.4 `VideoPlayback` and `AVVideoPlayback`

The controller talks to a small protocol so tests can use a fake, and so the controller never imports AVFoundation. `VideoPlayback.swift` goes in `App/Features/Player/State/`:

```swift
import CoreGraphics

/// The silent video player as the controller sees it: seven reads and four commands, and no
/// AVFoundation, so tests drive the controller with a fake.
@MainActor
protocol VideoPlayback: AnyObject {
    /// The item is ready to play and its picture size is known.
    var isReady: Bool { get }
    /// The item or the player has failed for good.
    var hasFailed: Bool { get }
    var positionMs: Int { get }
    /// Zero until known.
    var durationMs: Int { get }
    var isPlaying: Bool { get }
    /// Waiting for data, or for a jump to land.
    var isBuffering: Bool { get }
    var videoSize: CGSize { get }

    /// Fire and watch: returns at once, and a jump in flight counts as buffering until it lands.
    func seek(toMs ms: Int)
    func play()
    func pause()
    /// Stops the player and lets go of everything it holds. Safe to call twice.
    func teardown()
}
```

`AVVideoPlayback.swift` is the only file in this feature that imports AVFoundation besides the surface. `AVPlayer` owners live under `App/Platform/` (`Ads`, `Audio`), so it goes in a new folder, `App/Platform/Video/`:

```swift
import AVFoundation
import CoreGraphics

/// The real silent video: an `AVPlayer` that cannot be heard and that the audio engine knows nothing
/// about.
///
/// It is silent twice over (`isMuted` and `volume`) and never touches `AVAudioSession`: the audio
/// engine owns the session, and this player only draws. Every call is a no-op once `teardown()` has
/// run.
@MainActor
final class AVVideoPlayback: VideoPlayback {
    /// What the surface draws.
    let player: AVPlayer

    /// The key the audio engine already hands `AVURLAsset` for its own headers. It is in no SDK header
    /// (the symbol is exported all the same), so it is spelled here the way the engine spells it.
    private static let headerFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    private let item: AVPlayerItem
    /// Jumps asked for that have not reported back. A count, because a newer jump cancels an older one
    /// and both report back. Readable so a test can see it; nothing else sets it.
    private(set) var seeksInFlight = 0
    /// Where the newest of them is going.
    private var inFlightTargetMs: Int?
    private var isTornDown = false

    init(url: URL, headers: [String: String]) {
        let options: [String: Any]? = headers.isEmpty ? nil : [Self.headerFieldsKey: headers]
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .pause
        // A decoration for the audio, never a video to hand to an AirPlay screen.
        player.allowsExternalPlayback = false
        self.item = item
        self.player = player
    }

    // MARK: VideoPlayback

    var isReady: Bool {
        !isTornDown && item.status == .readyToPlay
            && item.presentationSize.width > 0 && item.presentationSize.height > 0
    }

    var hasFailed: Bool {
        !isTornDown && (item.status == .failed || player.status == .failed)
    }

    var positionMs: Int { isTornDown ? 0 : Self.milliseconds(player.currentTime()) }

    var durationMs: Int { isTornDown ? 0 : Self.milliseconds(item.duration) }

    /// `rate` is what was asked for, and stays so while the player waits for data; `isBuffering` tells
    /// those two apart.
    var isPlaying: Bool { !isTornDown && player.rate != 0 }

    var isBuffering: Bool {
        !isTornDown && (seeksInFlight > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
    }

    var videoSize: CGSize { isTornDown ? .zero : item.presentationSize }

    func seek(toMs ms: Int) {
        guard !isTornDown else { return }
        let target = max(0, ms)
        // `currentTime()` keeps reporting the old position until a jump lands, so a paused scrub
        // that is slow to land looks, every period, like a video still waiting to be moved. Asking
        // again for the same time would cancel the jump under way and start it over.
        if seeksInFlight > 0, inFlightTargetMs == target { return }
        seeksInFlight += 1
        inFlightTargetMs = target
        // Zero tolerance: the default lets the player land on a keyframe seconds away.
        player.seek(
            to: CMTime(value: CMTimeValue(target), timescale: 1_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in self?.seekReported() }
        }
    }

    func play() {
        guard !isTornDown else { return }
        player.play()
    }

    func pause() {
        guard !isTornDown else { return }
        player.pause()
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Private

    private func seekReported() {
        seeksInFlight = max(0, seeksInFlight - 1)
        if seeksInFlight == 0 { inFlightTargetMs = nil }
    }

    /// Zero for a time that is not a number yet (an item that has not loaded reports an indefinite
    /// duration).
    private static func milliseconds(_ time: CMTime) -> Int {
        guard time.isNumeric else { return 0 }
        let seconds = time.seconds
        return seconds.isFinite ? max(0, Int((seconds * 1_000).rounded())) : 0
    }
}
```

How each Flutter call maps:

| Flutter (`VideoPlayerController`) | `VideoPlayback` | AVFoundation |
| --- | --- | --- |
| `value.isInitialized` and a non-empty `value.size` | `isReady` | `item.status == .readyToPlay` and a non-empty `item.presentationSize` |
| `value.hasError` | `hasFailed` | `item.status == .failed \|\| player.status == .failed` |
| `await controller.position` | `positionMs` | `player.currentTime()` in ms |
| `value.duration` | `durationMs` | `item.duration` in ms; 0 while it is not a number |
| `value.isPlaying` | `isPlaying` | `player.rate != 0` |
| `value.isBuffering` | `isBuffering` | `seeksInFlight > 0 \|\| player.timeControlStatus == .waitingToPlayAtSpecifiedRate` |
| `value.size` | `videoSize` | `item.presentationSize` |
| `seekTo(...)` | `seek(toMs:)` | `player.seek(to:toleranceBefore:toleranceAfter:completionHandler:)` with zero tolerance |
| `play()`, `pause()` | `play()`, `pause()` | `player.play()`, `player.pause()` |
| `dispose()` | `teardown()` | `player.pause()`, then `player.replaceCurrentItem(with: nil)` |

Notes:

- **Muted twice, before anything plays.** `init` sets `isMuted = true` and `volume = 0` straight after creating the player, before the first `play()`. Always mute, even though the backend's split makes the video silent: when a creator uploads both files nothing is split and the video may have sound.
- **No `AVAudioSession`.** The file never calls it (section 6.1). A muted `AVPlayer` beside the engine's is expected not to interrupt the engine; that is not proven on iOS until device checks 2 and 7.
- **Headers are attached in `init`**, with the same string key the engine uses (section 6.9; risk R19).
- **Poll, do not observe.** The sync loop already runs every 250 ms, so everything is read on demand on the main actor. That avoids `@Sendable` KVO closures under Swift 6 strict concurrency. Do not add KVO or notifications. (The house pattern in `AdPacingController` uses KVO with a generation counter; this port deliberately does not.)
- **`currentTime()` and a jump in flight.** On macOS, `currentTime()` read straight after `seek(to:)` kept the old position (0 ms right after `seek(12345)`) until the jump landed. What iOS reports is not established. The code works either way: a jump in flight counts as buffering (`seeksInFlight > 0`), which holds the reveal and, while playing, stops a second jump stacking up. It is a count rather than a flag because a newer jump cancels an older one and both report back.
- **A jump asked for again while the same one is in flight is dropped.** A paused scrub that is slow to land would otherwise be re-asked every 250 ms, and each new request cancels the one under way and starts over. Once the jump has landed, the same time is a new jump.
- **Zero tolerance** (`toleranceBefore: .zero, toleranceAfter: .zero`). The defaults land on keyframes that can be seconds away, which the planner would then correct again and again. Zero tolerance costs decode time on long-GOP video (risk R4).
- **The seek completion hops to the main actor** (`Task { @MainActor in ... }`); the handler itself is `@Sendable`.
- **`isPlaying` is `rate != 0`.** Apple's documentation says `rate` is what was asked for and stays non-zero while the player waits for data, so a stalled video reads as playing and buffering. The planner copes (it never re-issues `play` while buffering, and a second `play()` is harmless). This is from the documentation, not from a test (risk R20).
- **No failure counters.** Flutter counts three failed passes in a row before it gives up, because its platform calls can throw. `AVPlayer.play()`, `pause()` and `seek` cannot fail that way. The only give-up signal on iOS is `hasFailed` (item or player status `.failed`), which gives up at once. An item that stays `.unknown` for ever just means the cover stays (Flutter behaves the same when `initialize()` hangs). Do not invent a timeout (risk R21).
- **`actionAtItemEnd = .pause`** is set explicitly so a video that ends before the audio holds its last frame; `allowsExternalPlayback = false` keeps a decoration for the audio from being offered to an AirPlay screen. `automaticallyWaitsToMinimizeStalling` stays at its default.
- **`teardown()` is safe twice**, and every call after it is a no-op that reads zeros.

### 6.5 `PlayerVideoController` and its loop

`App/Features/Player/State/PlayerVideoController.swift`. It owns one `VideoPlayback` and the per-open state, and mirrors the Dart (`_elapsed`, `_lastSeekAt`, `_outOfSyncSince`):

```swift
import CoreGraphics
import Foundation
import Observation

/// Keeps one silent video with the audio, and decides when its picture may show.
///
/// It reads the audio through an `AudioClock`, which cannot command it, and drives one `VideoPlayback`
/// by the plan `VideoSync` makes. It owns no timer: whoever attached the player calls `tick()` every
/// `VideoSync.reconcileIntervalMs`. That keeps this type free of tasks, and lets a test run seconds of
/// playback in an instant.
@MainActor
@Observable
final class PlayerVideoController {
    /// The picture is the right frame and may show over the cover.
    private(set) var isShown = false
    /// The video cannot be played. Stays set until the next `attach(_:)`, so the view can say so once.
    private(set) var hasFailed = false
    /// The picture's size; zero until known.
    private(set) var videoSize: CGSize = .zero

    private let clock: any AudioClock
    private let songId: String

    // Sync state. None of it is drawn, so none of it is observed.
    @ObservationIgnored private var playback: (any VideoPlayback)?
    /// Time as the loop counts it: the sum of the periods that have gone by. Cooldowns and grace
    /// periods run on this rather than the wall clock, so a test's fake time holds them the same.
    @ObservationIgnored private var elapsedMs = 0
    @ObservationIgnored private var lastSeekAtMs: Int?
    @ObservationIgnored private var outOfSyncSinceMs: Int?

    init(clock: any AudioClock, songId: String) {
        self.clock = clock
        self.songId = songId
    }

    /// Starts following the audio with `playback`, letting go of any player held before.
    func attach(_ playback: any VideoPlayback) {
        release()
        if hasFailed { hasFailed = false }
        self.playback = playback
    }

    /// One look at both players, and whatever it takes to bring the video back to the audio. Call it
    /// every `VideoSync.reconcileIntervalMs`, and once right away.
    func tick() {
        guard let playback else { return }
        if playback.hasFailed {
            fail()
            return
        }
        // Still opening: nothing to line up yet, and no time has been counted.
        guard playback.isReady else { return }
        reconcile(playback)
        elapsedMs += VideoSync.reconcileIntervalMs
    }

    /// Lets go of the player, if there is one. Safe at any time and any number of times. Leaves
    /// `hasFailed` as it was.
    func release() {
        playback?.teardown()
        playback = nil
        elapsedMs = 0
        lastSeekAtMs = nil
        outOfSyncSinceMs = nil
        if isShown { isShown = false }
        if videoSize != .zero { videoSize = .zero }
    }

    // MARK: Private

    private func fail() {
        release()
        if !hasFailed { hasFailed = true }
    }

    private func reconcile(_ playback: any VideoPlayback) {
        if videoSize != playback.videoSize { videoSize = playback.videoSize }

        // The audio is read next to the video so the two readings are as close in time as can be.
        let audio = AudioReading(
            positionMs: clock.positionMs,
            isReady: clock.isReady && clock.mediaId == songId,
            isPlaying: clock.isPlaying
        )
        let video = VideoReading(
            positionMs: playback.positionMs,
            durationMs: playback.durationMs,
            isPlaying: playback.isPlaying,
            isBuffering: playback.isBuffering
        )
        let plan = VideoSync.plan(
            audio: audio,
            video: video,
            sinceLastSeekMs: lastSeekAtMs.map { elapsedMs - $0 }
        )

        // Decided from the readings above, before the plan is carried out: a jump about to be made
        // says nothing about the frame on screen now.
        updateShown(audio: audio, video: video)

        if let target = plan.seekToMs {
            lastSeekAtMs = elapsedMs
            playback.seek(toMs: target)
        }
        if plan.play == true {
            playback.play()
        } else if plan.play == false {
            playback.pause()
        }
    }

    private func updateShown(audio: AudioReading, video: VideoReading) {
        if audio.isReady, VideoSync.drift(audio: audio, video: video) > VideoSync.hideDriftMs {
            if outOfSyncSinceMs == nil { outOfSyncSinceMs = elapsedMs }
        } else {
            outOfSyncSinceMs = nil
        }
        let shown = VideoSync.nextShown(
            shown: isShown,
            audio: audio,
            video: video,
            outOfSyncForMs: outOfSyncSinceMs.map { elapsedMs - $0 } ?? 0
        )
        if shown != isShown { isShown = shown }
    }
}
```

- **No timer.** Whoever attached the player calls `tick()` every `VideoSync.reconcileIntervalMs` (the layer in 6.6 does). Tests call `tick()` directly with a fake `VideoPlayback` and a fake `AudioClock`, so seconds of playback take no real time.
- **Virtual time.** `elapsedMs` grows by 250 per counted tick. Cooldowns and the hide grace run on it, not on the wall clock.
- **The first look is at elapsed 0.** A tick where the player is not ready yet counts no time, so the time spent opening is not held against the seek cooldown.
- **Order inside one look:** read the audio, read the video, plan, update `isShown` from those two readings, and only then seek (setting `lastSeekAtMs`) and play or pause. `isShown` is decided before the plan is carried out because a jump about to be made says nothing about the frame on screen now. Seek, play and pause are not awaited.
- **Read order differs from Flutter, on purpose.** Flutter reads the video position first because that read is asynchronous, then the audio. On iOS both reads are synchronous in one main-actor turn, so the order does not matter and the Swift reads the audio first.
- **Another episode's audio counts as not ready** (`clock.mediaId == songId`): no jump, no play, and the picture stays down.
- **Failure.** `playback.hasFailed` leads to `fail()`: the player is torn down, state is reset and `hasFailed` is set, once. It stays set until the next `attach(_:)`, so the view can report it once. `release()` leaves `hasFailed` as it was; `attach(_:)` releases what it held and clears it.
- **`songId` is immutable**, so one controller serves one song. That is why the layer is rebuilt per song (section 6.6).
- **Only `isShown`, `hasFailed` and `videoSize` are observed.** The rest is `@ObservationIgnored` because nothing draws it, and every write is guarded (`if x != y`) so an unchanged value never invalidates a view.

### 6.6 `PlayerVideoLayer`: lifetime with `.task(id:)`

> **Status: design.** This file was type-checked on macOS with stand-ins for `VideoSurface` and `MotionDuration.crossfade`. It has not run. Sections 6.2 to 6.5 ran; this one did not.

Flutter needs a generation counter because a release can land in the middle of an `await`. On iOS, let SwiftUI own the lifetime. `App/Features/Player/Components/PlayerVideoLayer.swift`:

```swift
import AVFoundation
import SwiftUI

/// One episode's silent video, drawn over its cover. The slot gives it
/// `.id(PlayerVideoLayerKey(songId:url:))`, so another episode, or another file for the same
/// episode, is a new layer with a new controller.
struct PlayerVideoLayerKey: Hashable {
    let songId: String
    let url: URL
}

struct PlayerVideoLayer: View {
    let url: URL
    let isVisible: Bool
    let makeHeaders: @Sendable () async -> [String: String]
    let onUnavailable: @MainActor () -> Void

    @State private var controller: PlayerVideoController
    @State private var playback: AVVideoPlayback?

    init(
        songId: String,
        url: URL,
        clock: any AudioClock,
        isVisible: Bool,
        makeHeaders: @escaping @Sendable () async -> [String: String],
        onUnavailable: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.isVisible = isVisible
        self.makeHeaders = makeHeaders
        self.onUnavailable = onUnavailable
        // SwiftUI keeps the first controller it is given and drops the rest.
        _controller = State(initialValue: PlayerVideoController(clock: clock, songId: songId))
    }

    var body: some View {
        GeometryReader { box in
            if let playback, controller.videoSize != .zero {
                VideoSurface(player: playback.player, gravity: gravity(in: box.size))
                    .opacity(controller.isShown ? 1 : 0)
                    .animation(.easeOut(duration: MotionDuration.crossfade), value: controller.isShown)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isVisible) { await run() }
    }

    private func gravity(in box: CGSize) -> AVLayerVideoGravity {
        let size = controller.videoSize
        let fit = VideoSync.fit(
            videoAspect: size.height > 0 ? size.width / size.height : 0,
            boxAspect: box.height > 0 ? box.width / box.height : 0
        )
        return fit == .cover ? .resizeAspectFill : .resizeAspect
    }

    private func run() async {
        guard isVisible else { return }
        let headers = await makeHeaders()  // the token is fetched here; cancellation-safe
        guard !Task.isCancelled else { return }
        let opened = AVVideoPlayback(url: url, headers: headers)
        playback = opened
        controller.attach(opened)
        defer {  // runs on cancel: hidden, or off the tree
            controller.release()
            playback = nil
        }
        controller.tick()  // a first look at once; a no-op until the item is ready
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(VideoSync.reconcileIntervalMs))
            guard !Task.isCancelled else { return }
            controller.tick()
            if controller.hasFailed {
                onUnavailable()
                return
            }
        }
    }
}
```

- **`.task(id: isVisible)`.** SwiftUI cancels the task when the layer leaves the tree or `isVisible` changes. The `defer` then runs: it tears the player down and clears the surface. That is how "switching to audio disposes the video", "the app goes to the background" and "a page pushed over the player" all release the player (section 6.7).
- **The token is fetched inside the task** (`makeHeaders`). The cancellation check right after it means a layer that was hidden while the token was being fetched never opens a player.
- **The first `controller.tick()`** runs straight after the player is attached. It does nothing until the item is ready; the loop then looks every 250 ms.
- **A hard failure** calls `onUnavailable()` once and returns; the `defer` releases the player. The slot answers by returning the mode to the cover and showing the toast (section 6.8).
- **The slot gives the layer `.id(PlayerVideoLayerKey(songId:url:))`** (section 6.11). Another episode, or another file for the same episode, is a new layer with a new controller (Flutter uses `ValueKey('$songId|${source.url}')` for the same reason).
- **`isVisible` is deliberately not in the key.** Hiding changes the task id, which cancels the loop and releases the player; showing again opens a fresh one on the same controller, because `attach(_:)` releases and clears.
- **The stale-`songId` trap.** The controller holds an immutable `songId`, and `@State` keeps the first controller it is given. A layer that was handed a new `songId` without a new identity would keep the old controller and compare the audio with the wrong episode for ever. The `.id(...)` is what prevents it.
- **The throwaway `State(initialValue:)`** that SwiftUI builds each time the parent re-evaluates is cheap (the controller owns no timer and no player until `attach`) and is dropped.
- **`VideoSurface` and `MotionDuration.crossfade` are new** (section 6.10): a shared surface extracted from `AdBreakView.swift`, taking an `AVPlayer` and a gravity, and a 0.22 s token. `run()` carries no `@MainActor` because the layer is a `View`, and it compiled that way against the macOS 26 SDK. The iOS SDK in the project's Xcode was not checked; if its compiler objects to the isolation of `run()`, mark it `@MainActor`.

### 6.7 Visibility rules (mapping Flutter to SwiftUI)

| Flutter | iOS |
| --- | --- |
| App `paused` / `hidden` / `detached` releases; `inactive` does not | `scenePhase == .background` releases; `.active` and `.inactive` keep it |
| `TickerMode` disabled (a full page pushed over the player) releases | `!coordinator.playerPath.isEmpty` releases |
| Sheets do not release | The sheet flags in `isPlayerUncovered` must **not** be used for the video. Use `scenePhase != .background && coordinator.playerPath.isEmpty` |
| Removed from the tree disposes | `.task` cancellation disposes |
| Ad break | `FullPlayerView` already swaps its body to `AdBreakView` during a break, so the layer leaves the tree and is released; it opens again after the break |

Pass the combined `isVisible` down explicitly (the existing code passes `isUncovered` into `PlayerAdOverlay` the same way) rather than reading the coordinator deep in the pager. Also confirm the full player really leaves the view tree when it is collapsed to the mini player. If it stays alive off-screen, gate the slot on the expanded state too (risk R15).

### 6.8 Failure handling

- `onUnavailable` runs once per open: `modeStore.showCover()` then a toast with "Video isn't available right now" through the same toast center `FullPlayerView` already uses (`@Environment(\.toastCenter)`; grep its existing call sites for the call shape). The audio is not touched.
- A `videoFile` that is non-empty but cannot be turned into a URL counts as unavailable too (Flutter: a throwing `Uri.parse` gives up with "could not create the player").
- After a failure the toggle is back on "Switch to video", and tapping it tries again from scratch (a new layer and a new `.task`).
- A file that opens but never becomes ready gives no failure signal, so there is no toast and the cover stays (measured on macOS: `avi` with MPEG-4 or H.264, HEVC tagged `hev1`; risks R1 and R21). Do not add a timeout without asking the user.

### 6.9 Source and headers

Add an internal method to `AudioSourceResolver` in the same file, reusing `proxyURL(for:base:)`:

```swift
func videoURL(forKey key: String) -> URL?   // /proxy?path=<encoded key>, same encoding as audio
```

Mirror whatever the resolver already does for `audioFile` when the value is not a bare key (absolute URLs, leading slashes): read the existing audio path first and copy its rules.

Headers must be the same as the engine's, because the same proxy and the same auth middleware serve both: `Authorization: Bearer <token>` with the token from `await tokenProvider.validAccessToken() ?? ""`, and the engine's `Content-Type: application/json`. Build them with a tiny shared helper so there is one definition, but **do not change `AudioEngine.makePlayerItem` in this feature**; leave a note to adopt the helper there later. `AVVideoPlayback.init(url:headers:)` attaches them itself, with the same string key the engine uses (section 6.4).

The token is fetched inside the layer's task, when the video opens (section 6.6). A long episode keeps the old headers for that player's life, which is fine because the first request is answered with a redirect to a signed URL, and that URL is what authorises the bytes; a reopened player fetches a fresh token.

**What was measured** (macOS, plain HTTP, a command-line tool; not the app). Two local servers stood in for the proxy (A, which answers 302) and for the signed target (B), and `AVVideoPlayback` was opened with an `Authorization` header:

| Set-up | Request the server saw | `Authorization` arrived? |
| --- | --- | --- |
| Direct URL, header set | both range requests | yes, on both |
| Through the 302, header set | A: `/api/proxy?path=clip`, `bytes=0-1` | yes |
| Through the 302, header set | B: `/files/clip.mp4`, `bytes=0-1`, the first request after the redirect | **no** (dropped) |
| Through the 302, header set | B: `/files/clip.mp4`, `bytes=0-299611`, the next range request | **yes**, straight to B; A was not asked again |
| Through the 302, no header | every request | none |

In all three set-ups the item was ready in about 100 ms, and after `seek(5000)` and `play()` for 1.5 s the position read 6.57 to 6.60 s, playing, not buffering.

- `AVURLAssetHTTPHeaderFieldsKey` is **undocumented**: it is in no SDK header and is only an exported symbol in `AVFoundation.tbd`. The engine already uses the same string literal (risk R19).
- Observed: the header is dropped on the first request after a redirect and sent on the next range request. So against the real backend the signed CloudFront or S3 URL may see an `Authorization` header from its second request on. S3 rejects a request that carries both a presigned query signature and an `Authorization` header (known behaviour; not tested here). Check which target `USE_CLOUD_FRONT` selects in each environment (risk R3), and let device check 2 decide.
- Not exercised: App Transport Security, HTTPS, the real proxy, the real CloudFront or S3.

**Fallback (do not build it unless device check 2 needs it).** Resolve the 302 once with a `URLSession` task whose delegate implements `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` and calls `completionHandler(nil)`; read the `Location` header from the response; give `AVPlayer` that URL with no headers. It costs one extra round trip per open and ties the player's life to the signed URL's expiry (3 hours by default).

### 6.10 Surface and fit

- Extract `ReelVideoSurface` and `PlayerLayerView` from `AdBreakView.swift` into a shared `VideoSurface` (for example `App/Features/Player/Components/VideoSurface.swift`) with a `videoGravity: AVLayerVideoGravity` parameter. Keep the reel ad's call site on `.resizeAspect`; run its tests and preview to prove it did not change.
- The player's gravity comes from `VideoSync.fit`: `.cover` maps to `.resizeAspectFill`, `.contain` to `.resizeAspect`. Video aspect is `presentationSize.width / height`; box aspect is the layer's width over height (read it with a `GeometryReader`). Set `clipsToBounds = true` on the hosting view so a filled video is cropped to the box.
- Background behind the picture is the dark token, not a literal (`PlayerLayerView` currently uses black; take it from a parameter or token).
- The layer view: `.opacity(controller.isShown ? 1 : 0)`, animated with a new `MotionDuration` token of 0.22 s ease-out; `.allowsHitTesting(false)`; `.accessibilityHidden(true)`. Render nothing while there is no player, the item is not ready, or `videoSize` is empty. The layer in 6.6 calls `VideoSurface(player: AVPlayer, gravity: AVLayerVideoGravity)` and `MotionDuration.crossfade` (0.22); both are new.

### 6.11 Mode store, slot and pager

```swift
@MainActor @Observable
final class PlayerVideoModeStore {
    private(set) var showsVideo = false      // not persisted, by design
    func showVideo() { showsVideo = true }
    func showCover() { showsVideo = false }
    func toggle() { showsVideo.toggle() }
}
```

- Register it in `AppComposition.swift` right after the `EpisodeTimelineStore` registration and resolve it in `FullPlayerView` as `@State private var videoMode: PlayerVideoModeStore = DependencyContainer.current.resolve()`, matching how the other player dependencies are wired.
- `PlayerVideoSlot(song:isVisible:)` shows a layer only when **all three** hold: `videoMode.showsVideo`, the song has a source (`videoFile` non-empty), and the page's song is the one the engine is playing (`engine.currentSong?.id == song.id`). Put that decision in a small pure function so it can be unit-tested without UI. Any of the three turning false removes the layer, which releases the player. The slot gives the layer `.id(PlayerVideoLayerKey(songId: song.id, url: url))` (section 6.6), passes `isVisible` (section 6.7), and supplies `makeHeaders` (section 6.9) and `onUnavailable` (section 6.8).
- In `PlayerArtworkPager`, each song's page becomes the `ArtworkView` with the slot over it (a `ZStack`). Give any new pager initialiser parameters default values so `PlayerArtworkPagerTests` still compiles, then extend that test.
- `FullPlayerView.artwork(width:)`: inside the `PlayerAdOverlay` content, wrap the pager and the pill in a `ZStack(alignment: .bottomTrailing)`, so the ad overlay covers both:

```
FullPlayerView
  artwork(width:)
    PlayerAdOverlay { ...
      ZStack(alignment: .bottomTrailing) {
        PlayerArtworkPager      // per page: ArtworkView + PlayerVideoSlot
        MediaModeToggle         // empty unless the current song hasVideo
      }
    }
```

### 6.12 The pill, strings, icons, tokens

**Pill.** A `Button` whose label is `Image(systemName:)` (16 pt, `Dimens.iconSizeSmall`) plus `Text` in `Typography.labelMedium`, white, semibold, one line, truncating. Horizontal padding `Dimens.spacing12`, vertical `Dimens.spacing8`, gap `Dimens.spacing6`, capsule shape, background `PlayerStyle.artworkControlBackground` (black at 0x8C / 255, about 55 percent). The visible pill is smaller than a finger, so give the button a `contentShape` and a frame of at least `Spacing.minTapTarget` x `Spacing.minTapTarget`, with the pill centred in it. It is the **frame** that is offset, as in Flutter: `.padding(.trailing, Dimens.spacing4).padding(.bottom, Dimens.spacing2)` on the frame, inside the `ZStack(alignment: .bottomTrailing)` of section 6.11. Accessibility: button trait, label equal to the visible text. Use a flat translucent capsule for parity with Flutter and for legibility over any artwork. If `progress.md` decision D13 (Liquid Glass through `GlassSurface`) is read as covering every floating control, ask the user before switching to `GlassSurface(.clear, in: Capsule(), interactive: true)`.

**Icons.** Camera when the tap goes to video: SF Symbol `video.fill` (Flutter: `Icons.videocam_rounded`). Headphones when it goes to audio: `headphones` (Flutter: `Icons.headphones_rounded`). `IconToken` has no case for either (checked 2026-11-10), so add `.video` and `.headphones`, each with a `systemName` entry; `assetName` can stay on its `default: nil`.

**Strings.** Add three entries to `App/Resources/Localizable.xcstrings` (English text is the key) with all six languages. Look at an existing manual entry first and copy its formatting. Never concatenate translated fragments.

| Language | Switch to video | Switch to audio | Video unavailable |
| --- | --- | --- | --- |
| en | `Switch to video` | `Switch to audio` | `Video isn't available right now` |
| hi | `वीडियो पर स्विच करें` | `ऑडियो पर स्विच करें` | `अभी वीडियो उपलब्ध नहीं है` |
| kn | `ವೀಡಿಯೋಗೆ ಬದಲಿಸಿ` | `ಆಡಿಯೋಗೆ ಬದಲಿಸಿ` | `ಈಗ ವೀಡಿಯೋ ಲಭ್ಯವಿಲ್ಲ` |
| ml | `വീഡിയോയിലേക്ക് മാറുക` | `ഓഡിയോയിലേക്ക് മാറുക` | `ഇപ്പോൾ വീഡിയോ ലഭ്യമല്ല` |
| ta | `வீடியோவுக்கு மாறவும்` | `ஆடியோவுக்கு மாறவும்` | `இப்போது வீடியோ கிடைக்கவில்லை` |
| te | `వీడియోకి మారండి` | `ఆడియోకి మారండి` | `ప్రస్తుతం వీడియో అందుబాటులో లేదు` |

Entry shape (match the file's real formatting):

```json
"Switch to video" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Switch to video" } },
    "hi" : { "stringUnit" : { "state" : "translated", "value" : "वीडियो पर स्विच करें" } }
    /* kn, ml, ta, te the same way */
  }
}
```

**Tokens to add** (nothing hardcoded: no `Color(hex:)`, no `.padding(16)`): `PlayerStyle.artworkControlBackground`; a `MotionDuration` value of 0.22 s for the reveal; the dark background colour for behind the picture if no suitable `ColorToken` exists.

**Data model.**

- `Song`: add `var videoFile: String? = nil` after `episodeTimeline` (a default keeps every existing memberwise call compiling) and `var hasVideo: Bool { !(videoFile?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }`. **Copy it in `withFavorited(_:)`**, or favouriting an episode silently drops its video. Look for any other helper that rebuilds a `Song` the same way.
- `SongDTO`: add an optional `videoFile`, decoded leniently like the other podcast fields (decision D25: new podcast fields are optional and additive). Pass it, sanitised the way `audioFile` is, in `toDomain()`.
- If `Song` is `Codable` or stored anywhere (queue snapshot, history, downloads), an optional property decodes as `nil` from old payloads; confirm that rather than assuming it. If a GRDB record type mirrors `Song`, decide with the user whether to add the column (a migration) or leave offline songs without video.
- `Tests/Support/Fixtures/SongFixture.swift`: add a `videoFile` parameter with a `nil` default.

---

## 7. Implementation steps (in order; build and test after each)

1. **Data.** `Song.videoFile` and `hasVideo`, `withFavorited`, `SongDTO` and `toDomain`, `SongFixture`. Before moving on, fetch one real episode's JSON from the dev backend and confirm the `videoFile` key is present in a feed response (risk R2). If it is not, stop and tell the user: it is a backend change.
2. **Source.** `AudioSourceResolver.videoURL(forKey:)` and the shared headers helper. Tests.
3. **Policy.** Paste `VideoSync.swift` (with `AudioReading`, `VideoReading`, `VideoSyncPlan`) from section 6.3 into `App/Features/Player/State/`. Tests from the tables in section 8.1.
4. **Clock.** Paste `AudioClock.swift` (the protocol and `EngineAudioClock`) from section 6.2. Change it only where it meets the real `AudioEngine.Status`, and keep the `switch` exhaustive.
5. **Mode.** `PlayerVideoModeStore`, registration in `AppComposition`, tests.
6. **Surface.** Extract `VideoSurface` from `AdBreakView.swift` with a gravity parameter. The reel ad must render and test exactly as before.
7. **Controller.** Paste `VideoPlayback.swift` and `PlayerVideoController.swift` into `App/Features/Player/State/`, and `AVVideoPlayback.swift` into a new `App/Platform/Video/` (sections 6.4 and 6.5), with small changes only. Tests with a fake playback and a fake clock (sections 8.2 and 8.3).
8. **Views.** `PlayerVideoLayer` (section 6.6; it was only type-checked, so expect compile fixes), `PlayerVideoSlot` and the pager integration (section 6.11, design only).
9. **Pill and wiring.** `MediaModeToggle`, `FullPlayerView` placement, tokens, `IconToken` cases, String Catalog entries, previews (light and dark, both states of the pill; the layer with a fake playback).
10. **Verify.** `make lint` (the first lint this Swift has had), `make test`, clean Debug and Release builds with zero new warnings, run on the simulator, then on a device (section 9). Confirm `grep -rn AudioEngine` and `grep -rn AVAudioSession` over the new files come back clean (section 6.1).
11. **Bookkeeping.** Add an item and decision D26 to `progress.md` ("silent video mode: the audio is the clock"). A-items run to A14 but A7 mentions "A15/Q7", so read `progress.md` and pick the next free id before writing. No `TODO` without an item id.

---

## 8. Tests (Swift Testing)

**The specification is the Flutter test folder** `/Users/teja/company/projects/projectH/project-h-workspace/app/test/features/podcast/`. Read `video_sync_test.dart` first. The Flutter doc reports 107 tests passing in six files there. They were written by a parallel session, and they were not re-run when this file was written.

Every number below is one that a throwaway macOS harness checked against the Swift in sections 6.2 to 6.5: **179 checks, all passing** (the planner table mirrors every case of `video_sync_test.dart`; then the 13 controller scenarios against fakes; then `AVVideoPlayback` on a local mp4; then an end-to-end run). The harness lived in a session scratchpad and is **not kept**, so the checks still have to be written as Swift Testing tests. This section is the checklist and gives the expected values. If a test fails when you first run it, suspect the test or the paste before the design: the same numbers passed in the harness.

| Flutter test file | Tests | iOS counterpart |
| --- | --- | --- |
| `video_sync_test.dart` | 43 | `VideoSyncTests`: pure, tables 8.1 |
| `player_video_layer_test.dart` | 33 | `PlayerVideoControllerTests` (a fake clock and a fake playback, 8.2) and the `AVVideoPlayback` checks (8.3). The SwiftUI layer needs a preview, not a unit test |
| `player_video_slot_test.dart` | 22 | the slot's pure decision function and `MediaModeToggle` (sections 6.11 and 6.12) |
| `player_video_mode_provider_test.dart` | 6 | `PlayerVideoModeStoreTests` |
| `song_has_video_test.dart` | 3 | `Song` tests for `hasVideo` |
| `video_fakes.dart` | | `FakeAudioClock` and `FakeVideoPlayback` in `Tests/Support/`. The harness's `FakeClock` and `FakePlayback` are the model (8.2) |

The Dart groups in `player_video_layer_test.dart` and their closest iOS counterparts (the Dart is the specification; open it for the cases):

| Dart group | iOS |
| --- | --- |
| 'the player it opens' | the "muted" and "ready" checks in 8.3; device check 2 |
| 'following the audio' | controller scenarios 1 to 4 and 8 |
| 'the audio is not the video's to trust' | scenarios 9 and 10 |
| 'letting go of the player' | scenario 13; the lifetime itself is `.task(id:)`, so device checks 5, 6 and 8 |
| 'when the video cannot be played' | scenario 12 |
| 'a player that only hiccups is not given up on' | **no counterpart.** Flutter-only: its platform calls can throw and it counts three failures in a row. `AVPlayer` calls do not throw (section 6.4) |

The Dart groups in `player_video_slot_test.dart`: 'the slot opens a player only when all three agree' and 'the player follows the choice and the episode' map to the slot decision function and the `.id(...)` key (section 6.6); 'the switch' and 'the switch and the slot together' map to `PlayerVideoModeStore` and `MediaModeToggle`; 'when the video cannot be played' maps to `onUnavailable` calling `showCover()` and showing the toast (section 6.8).

### 8.1 The planner: `VideoSyncTests`

Defaults unless a row says otherwise: audio ready and playing at 10,000; video playing at 10,000, not buffering; video duration 1,800,000 (30 min); no previous seek. A plan is written `(seekToMs, play)`; "no-op" is `isNoop`.

**Constants:** playing tolerance 300, paused tolerance 120, playing seek cooldown 1500, paused seek cooldown 250, seek lead 200, tail guard 150, hide drift 1500, hide grace 1000; and the lead (200) is below the playing tolerance (300).

**`VideoSync.plan`**

| Case | Expected |
| --- | --- |
| Audio not ready, video playing | `(nil, false)` |
| Audio not ready, video paused | no-op |
| Audio not ready, video at 0 and paused | `seekToMs` is nil (it never jumps) |
| Video at 10300 or 9700 (300 off) | no-op |
| Video at 10301 or 9699 (301 off) | `(10200, nil)` |
| Video at 0, since the last seek 1499 / 1500 / nil | no seek / `seekToMs` 10200 / `seekToMs` 10200 |
| Video at 0, paused and buffering | no-op |
| Video paused, in step | `(nil, true)` |
| Video paused, in step, buffering | no-op |
| Video at 0 and paused | `(10200, true)` (catches up in one pass) |
| Audio paused, video paused at 9880 or 10120 (120 off) | no seek |
| Audio paused, video paused at 9879 or 10121 (121 off) | `seekToMs` 10000 |
| Audio paused, video at 0 and paused | `(10000, nil)` (lands exactly on the audio) |
| Audio paused, video at 0 and paused, since the last seek 249 / 250 | no seek / `seekToMs` 10000 |
| Audio paused, video playing and in step | `(nil, false)` |
| Audio paused, video at 0, paused and buffering | `seekToMs` 10000 (still jumped to the frame) |
| Duration 600000, video paused at the audio position; audio at 599849 / 599850 / 599851 | `play` is true / nil / nil |
| Duration 600000, video playing at 0; audio at 599600 / 599840 | `seekToMs` 599800 / 599850 (capped by the end) |
| Duration 600000, audio 599900, video 599700, video playing | `(599900, false)` |
| Duration 60000, audio 90000, video at 0 and paused | `(60000, nil)` (a short video holds its last frame) |
| Duration 60000, audio 90000, video at 60000 and paused | no-op |
| Duration 0 (unknown), audio 10000, video at 0 and paused | `(10200, true)` |
| `VideoSyncPlan()` | `isNoop` |
| `(nil, false)` and `(0, nil)` | both are **not** no-ops (a pause is a command; a seek to 0 is a seek) |

**`VideoSync.drift`**

| Audio, video, duration | Expected |
| --- | --- |
| 10000, 10400 | 400 |
| 10000, 9600 | 400 |
| 10000, 10000 | 0 |
| 90000, 60000, duration 60000 | 0 (measured to the video's end) |
| 90000, 0, duration 60000 | 60000 |
| 90000, 60000, duration 0 | 30000 (no length known, no end to clamp to) |

**`VideoSync.nextShown`.** Default: was hidden; audio ready and playing at 10,000; video playing at 10,000, not buffering; out of sync for 0 ms. (The harness helper always passes a playing video.)

| Case | Expected |
| --- | --- |
| Audio not ready, was shown, video at 0, out of sync 60000 | stays shown |
| Audio not ready, was hidden | stays hidden |
| Video at 10300 / 9700 | shown (300 off is in step) |
| Video at 10301 / 9699 | hidden |
| Audio paused, video at 10120 / 9880 | shown |
| Audio paused, video at 10121 / 9879 | hidden |
| Buffering | hidden |
| Audio 599900, video 599700, duration 600000 | hidden (near the end the paused tolerance applies) |
| Audio 500000, video 499800, duration 600000 | shown (200 off in mid-video is fine) |
| Audio paused, video at 0 | hidden (a video that is out is not brought up by a pause) |
| Was shown, video 11500 (exactly 1500 off), out of sync 5000 | stays shown |
| Was shown, video 11501, out of sync 999 | stays shown |
| Was shown, video 11501, out of sync 1000 | goes hidden |
| Was shown, video 8499, out of sync 1000 | goes hidden |
| Was shown, video 8500, out of sync 1000 | stays shown |
| Was shown, buffering, in step | stays shown |
| Was shown, audio 90000, video 60000, duration 60000, out of sync 60000 | stays shown (a short video parked on its last frame) |
| Was hidden, audio 90000, video 60000, duration 60000 | comes up |

**`VideoSync.fit(videoAspect:boxAspect:)`**

| Video aspect, box aspect | Expected |
| --- | --- |
| 1.05, 1 | cover |
| 0.95, 1 | cover |
| 16/9, 16/9 | cover |
| 1.07, 1 | contain |
| 0.93, 1 | contain |
| 16/9, 1 | contain |
| 0, 1 and -1, 1 | contain |
| 1, 0 and 1, -1 | contain |

### 8.2 The controller: `PlayerVideoControllerTests`

Build a small rig: a `PlayerVideoController`, a fake clock and a fake playback, with fake time.

- `tick(n)` advances both fakes by 250 ms, `n` times, calling `controller.tick()` after each. `look()` is the first look with no time passing.
- `start(audioMs:videoMs:)` sets the audio playing at one position and parks the video at another.
- The fake clock has `positionMs`, `isPlaying`, `isReady` and `mediaId` (default `"ep1"`), and moves only while playing and ready.
- The fake playback records `seeks`, `plays`, `pauses` and `teardowns`, and has three switches: `frozen` (does not move when told to play), `ignoresSeeks` (takes no notice of a jump) and `seekLatencyMs` (a jump lands after that much fake time and reads as buffering until then). Its `isBuffering` is "a jump is pending".

The thirteen scenarios (song id `"ep1"`):

1. **Catch-up.** Audio playing at 5000, video parked at 0. After `look()`: `seeks == [5200]`, one play, the cover is still up (the video is far out). After one `tick()`: the picture is shown. After 20 more ticks: still one jump, one play, still shown.
2. **Already in step.** Audio 5000, video 5000. After `look()`: no jump, one play, and the picture is shown on the first look.
3. **Pause, resume, scrub.** In step at 5000; `look()` then 8 ticks: shown. The audio pauses, then one tick: one pause, the video is not playing. 4 more ticks. The audio position is set to 20000, then one tick: the last jump is exactly 20000 and plays is still 1. The audio resumes, then one tick: plays is 2 and the picture is shown.
4. **Pause after a catch-up.** Audio 5000, video 0; `look()` then 8 ticks; the audio pauses, then one tick: the last jump equals the audio position (the video had been a lead ahead, so it is put exactly on the audio).
5. **A frozen video.** In step at 5000; `look()`; the video becomes `frozen` and `ignoresSeeks`; after 10 ticks (2.5 s) the picture is still shown; after the 11th tick (2.75 s) the cover is back; exactly two jumps in all (at 0.5 s, then again after the cooldown, not between).
6. **The audio jumps 3 s.** In step at 5000; `look()` then 2 ticks; the video starts to ignore jumps; the audio position moves +3000; tick one at a time: the picture is shown up to the 4th look and the cover is back on the 5th.
7. **The second jump waits for the cooldown.** Audio 50000, video 0, `ignoresSeeks`; `look()` makes the first jump; over ticks 1 to 8 the only further jump comes on tick 6.
8. **A slow jump.** `seekLatencyMs` 1000; audio 5000, video 0; `look()` then 3 ticks: one jump only (not repeated while in flight), and the cover stays down.
9. **Another episode's audio.** `mediaId` is `"other"`; `look()` then 8 ticks: no jump, no play, nothing shown. Set `mediaId` back to `"ep1"`, then one tick: one jump and one play.
10. **Audio not ready while the video plays.** In step; `look()` then 4 ticks: shown. The audio becomes not ready; 3 ticks: exactly one pause, no jump, the picture keeps its state (still shown). Ready again, then one tick: plays is 2.
11. **A playback that is not ready yet.** Not ready; audio 5000, video 0; `look()` then 4 ticks: no commands at all. Make it ready, then `look()`: one jump. 5 more ticks: still one jump (the opening time was not counted against the cooldown).
12. **Failure.** In step; `look()` then 2 ticks; the playback reports `hasFailed`; one tick: the controller's `hasFailed` is set, the playback was torn down once, nothing is shown. 4 more ticks: still one teardown. Attaching a new playback clears `hasFailed`.
13. **Release and attach.** `look()`, then `release()` twice: torn down once, nothing shown. 2 ticks: no jump (no further reads or commands). Attach playback `a`, then attach `b`: `a` was torn down once. Set the audio to 9000 and tick: `a` has no jumps and `b` has some (only the new player is driven).

### 8.3 `AVVideoPlayback` on a real file

These need a real media file, so they go in their own test file, with the clip as a test resource (about 300 KB; ask the user whether to bundle it) or skipped when it is missing. A 40-second silent clip, **H.264 High, 320x240, yuv420p, 25 fps, 40.000 s, 1000 frames, a keyframe every second, video stream only**, made with:

```
ffmpeg -f lavfi -i testsrc=size=320x240:rate=25 -t 40 -g 25 -pix_fmt yuv420p -c:v libx264 -an -movflags +faststart clip.mp4
```

With ffmpeg 8.1.1 this reproduces the harness's file byte for byte (it came to 299,612 bytes); another ffmpeg gives an equivalent file, not an identical one. `waitUntil` below means "poll every 10 ms, give up after 5 s".

- **Open.** Before `waitUntil { isReady }`: not playing and not buffering. It becomes ready and has not failed. `durationMs` is within 100 ms of 40,000. `videoSize` is 320x240. `player.isMuted` is true and `player.volume` is 0. Not playing before `play()`, not buffering at rest.
- **A jump.** After `seek(toMs: 12_345)`, `isBuffering` is true at once (the position read straight after was 0 ms on macOS; log it, do not assert it). It lands (buffering clears), and `positionMs == 12_345` exactly.
- **Play and pause.** `play()`: `isPlaying` straight away, and the position passes 12,745. `pause()`: not playing straight away, and the position holds over 300 ms.
- **A jump while playing.** `play()` then `seek(toMs: 30_000)`: reads as buffering; it lands; the position is in 30,000 to 30,799 and it is still playing.
- **Two different quick jumps** (1000, then 2000): `seeksInFlight == 2`; both report back (buffering clears) and `seeksInFlight` returns to 0; the position ends within 800 ms of 2000.
- **The same jump asked again.** Paused; `seek(toMs: 7_000)` three times: `seeksInFlight == 1`; buffering clears; `positionMs == 7_000`. Once landed, `seek(toMs: 7_000)` again is a new jump (`seeksInFlight == 1`), and it lands too.
- **Teardown.** `teardown()` twice: not ready, not playing, not buffering, not failed; `positionMs == 0`; `seek`, `play` and `pause` afterwards leave it not playing and not buffering.
- **A missing file** (`/nonexistent/none.mp4`): `hasFailed` becomes true within 5 s, and it is not ready.

**Container behaviour (measured once, not a test).** This is what the planned `AVVideoPlayback` did with each container the backend accepts (risk R1), on macOS 26.5.2 (arm64), not on iOS. The clips were 2 s, 320x240, 25 fps, silent, made with ffmpeg 8.1.1, and each was given 3 s to answer:

```
mk() { ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=25 -t 2 "$@"; }
mk -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart h264.mp4
mk -c:v libx264 -pix_fmt yuv420p -an h264.mov
mk -c:v libx264 -pix_fmt yuv420p -an h264.mkv
mk -c:v libvpx-vp9 -pix_fmt yuv420p -deadline realtime -cpu-used 8 -an vp9.webm
mk -c:v libvpx -deadline realtime -an vp8.webm
mk -c:v mpeg4 -an mpeg4.avi
mk -c:v libx264 -pix_fmt yuv420p -an h264.avi
mk -c:v mjpeg -an mjpeg.avi
mk -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -an -x265-params log-level=error hevc_hvc1.mp4
mk -c:v libx265 -pix_fmt yuv420p -an -x265-params log-level=error hevc_hev1.mp4
```

| Clip | Result |
| --- | --- |
| `mp4` or `mov`, H.264 | Ready in 50 to 100 ms, and it plays (after a seek to 500 ms and 1 s of play the position read about 1.56 s). |
| `mp4`, HEVC tagged `hvc1` | Ready, and it plays. |
| `mp4`, HEVC tagged `hev1` (ffmpeg's default tag) | Never ready and never fails: the picture size is still 0x0 after 3 s. |
| `mkv`, H.264 | `hasFailed` at once ("Cannot Open"). |
| `webm`, VP8 or VP9 (profile 0, `yuv420p`) | `hasFailed` at once. |
| `avi`, MPEG-4 part 2 or H.264 | Never ready and never fails: the item reaches `readyToPlay` but the picture size is 0x0 (`isPlayable` is false, the duration reads 2000 ms). |
| `avi`, Motion JPEG | Ready, and it plays. |

`AVVideoPlayback.isReady` needs both `readyToPlay` and a non-zero picture size, which is why the two "never ready" rows keep the cover instead of showing a black frame. These are macOS results; device check 10 is the run on an iPhone.

### 8.4 End to end

A controller, the real `AVVideoPlayback` (wrapped in a counting `VideoPlayback` that forwards to it), and a fake clock that follows the wall clock (`play`, `pause`, `seek(toMs:)`), with a loop that calls `controller.tick()` every 250 ms the way the layer does.

- **Opening.** The clock seeks to 5000 and plays. Within 4 s the picture is shown, with at most 2 jumps. (Measured: shown after about 507 and 565 ms in two runs, with one play.)
- **Steady playback.** Over the next 4 s the drift stays at or below 500 ms (worst measured: 199 ms, which is the 200 ms lead), the picture stays shown, and the whole run so far has at most 3 jumps.
- **The audio pauses** (run 1.5 s): the video is not playing, it is within 120 ms of the audio, and the picture stays shown.
- **The audio resumes** (run 2.5 s): the video is playing and within 600 ms of the audio.
- **A paused scrub** to 20,000 (run 1.5 s): the video is within 120 ms and still paused. Then resume (run 2.5 s): within 600 ms, and the picture is shown.
- **The audio is not ready** (run 0.75 s): the video is not playing.
- **Release.** `release()`: the playback was torn down once and nothing is shown.

These depend on real time. If they are flaky on CI, run them locally only and say so in the report.

### 8.5 Other tests

- `Song`: `hasVideo` for nil, empty, whitespace-only and a real key. `withFavorited` preserves `videoFile`.
- `SongDTO`: decodes with the key, with `null`, with the key missing, and with a non-string value (must not fail the whole song).
- `AudioSourceResolver.videoURL`: the same encoding as audio, including a key with `&`, `=`, `+` and spaces.
- `PlayerVideoModeStore`: starts on the cover; `toggle`, `showVideo`, `showCover`.
- Slot decision function: video shows only when the mode is on, the song has a source and the page is the playing song; each one false hides it.
- Localization: if the repo has a completeness test for the String Catalog, run it; otherwise assert all three keys have six languages.
- Existing: `PlayerArtworkPagerTests` still passes; the reel ad surface still passes.

---

## 9. Device checks (nothing is verified until these are done)

1. A video episode shows the pill at the artwork's bottom trailing corner. A music track, and an episode without a video, show no pill and an unchanged player.
2. Tap it: the picture fades in within a second or two, at the audio's position. The audio does not gap or stutter at any point (watch the lock-screen elapsed time).
3. Pause the audio: the picture freezes on the same frame. Scrub: the frame follows the thumb.
4. Skip forward and back, and tap a chapter: the picture catches up without flashing the cover.
5. Switch to audio: the picture goes, audio uninterrupted. Check that the video URL is no longer being fetched.
6. Background the app in video mode: audio keeps playing, the video is released. Foreground: the picture comes back in step.
7. Lock screen and Control Center: Now Playing is still the audio, and the remote play/pause still controls it (risk R6).
8. Push a page over the player (an artist, say): video released. Pop: it returns. Open a sheet over the player: the video keeps running behind it.
9. Cut the network while in video mode. Two outcomes are possible, and both are acceptable; record which one you see. (a) A hard failure: the toast appears, the pill returns to "Switch to video", the audio carries on. (b) A stall with no failure: no toast; the picture freezes, the cover comes back once the video has been behind by more than 1.5 s for a second, and the video catches up when the network returns. Either way the audio must behave exactly as it does with the cover showing (risks R20 and R21).
10. Video-only episodes in the other containers (risk R1; the expectations come from macOS, not iOS, so record what an iPhone does). `webm` or `mkv`: expect the toast and the cover. `avi` with MPEG-4 or H.264, or `mp4` with HEVC tagged `hev1`: expect no toast and the cover staying (risk R21). `mp4` or `mov` with H.264, and HEVC tagged `hvc1`: expect them to play.
11. An ad break during video mode: the picture is gone for the break and back after it.
12. Speed 1.5x or 2x: note how the picture behaves (risk R9).
13. Watch for hitches while the video plays: scroll the queue sheet, drag the scrubber (decision: 120 fps, `Docs/PERFORMANCE.md`).
14. Pill taps never open an ad and never page the artwork (risk R8).
15. Dynamic Type at the largest size and VoiceOver (`Docs/ACCESSIBILITY.md`): the pill reads as a button with its label.

---

## 10. Risks and open questions

| # | Risk | What to do |
| --- | --- | --- |
| R1 | **AVFoundation does not open every container the backend accepts.** The backend allows `mp4`, `mov`, `avi`, `mkv` and `webm` uploads, and the silent copy keeps the upload's container and codec (stream copy). Measured on macOS 26.5.2 (not iOS), with 2 s silent clips and the planned `AVVideoPlayback` (section 8.3): `mp4` and `mov` with H.264 play. `mp4` with HEVC plays only when tagged `hvc1`; with the tag `hev1` (ffmpeg's default) the item never becomes ready and never fails. `mkv` with H.264 and `webm` with VP8 or VP9 fail at once. `avi` with MPEG-4 part 2 or H.264 never becomes ready and never fails (the item says `readyToPlay` but the picture size stays 0x0); `avi` with Motion JPEG plays. Hallelujah Flutter on iOS uses AVPlayer too (through `video_player`), so it is expected to be affected the same way; not tested there. Android was not checked. | The failure path (toast, cover) is the answer in this task. For the "never ready, never fails" cases the cover simply stays and there is no toast (risk R21, device check 10). Do not touch the backend. Tell the user: the follow-up is either restricting video-only uploads to `mp4` or `mov` (H.264, or HEVC tagged `hvc1`), or remuxing or transcoding the silent copy to mp4 in `videoAudioSplit.js` (HEVC needs `-tag:v hvc1`). It is their call. |
| R2 | `videoFile` arriving in feed responses is unverified. | Step 1. If absent, stop and report. |
| R3 | The proxy answers 302 to a signed URL while AVPlayer sends custom headers. If `USE_CLOUD_FRONT` is false the target is an S3 presigned URL, and S3 rejects a request carrying both a query signature and an `Authorization` header. Measured on macOS against a local HTTP server: the header is dropped on the first request after the redirect and sent on the next range request (section 6.9). | Video uses the same path as audio, so if audio streams, video streams; device check 2 is the proof. Check which target `USE_CLOUD_FRONT` selects in each environment. If the signed target rejects the extra header, use the fallback in section 6.9. |
| R4 | Zero-tolerance seeks on long-GOP video (camera footage with 5 to 10 s keyframe gaps) are slow, and every correction pays that cost. | The 1.5 s cooldown limits it. Measure on a real episode. |
| R5 | The silent video is stream-copied at its original bitrate, so it can multiply data use on cellular. | Not handled in Flutter either. Mention to the user. |
| R6 | A second `AVPlayer` might confuse Now Playing or remote commands. | Verify on device (check 7). If the system picks the video player, set `allowsExternalPlayback = false` on it and make sure only the engine writes Now Playing. |
| R7 | `AVPlayer.preventsDisplaySleepDuringVideoPlayback` defaults to true, so the screen would not auto-lock in video mode. Whether Hallelujah Flutter does the same is unverified. | Decide with the user. Leave the default until told otherwise. |
| R8 | Gestures: `PlayerAdOverlay` attaches a simultaneous tap and drag, and the pager is a paging `TabView`. | Confirm those gestures apply only while the ad card is showing, and that a pill tap triggers neither. |
| R9 | No playback-speed mirroring (same as Flutter). At speeds other than 1x the picture drifts and is corrected by seeks every 1.5 s or so. | Known limitation. A fix is `player.rate = engine rate`, but do it in both apps, in a follow-up. |
| R10 | Mode is not persisted (same as Flutter). | By design. |
| R11 | Offline or downloaded episodes still show the pill, and tapping it ends in the unavailable toast. | Parity with Flutter. Mention to the user. |
| R12 | `RecentSearchStore.swift:54` and `CarPlayContentProvider.swift:348` rebuild a `Song` without `videoFile`, so an episode started from there has no pill until its data is refreshed. | Acceptable. Decide with the user whether to carry the field. |
| R13 | Token expiry mid-episode. | Low: headers are used for the redirect, and a reopened player fetches a fresh token. A signed URL lasts 3 hours by default, as for audio. |
| R14 | `AdBreakView` replaces the player body during a break, so the layer is torn down and rebuilt. | Check 11. |
| R15 | Unknown whether the full player leaves the view tree when collapsed. | Confirm in `FullPlayerView` and the coordinator. If it stays alive, gate the slot on the expanded state. |
| R16 | `AudioEngine.status` behaviour during a mid-playback stall (section 6.2). | Record what you see. Do not change the engine. |
| R17 | The pager is a `TabView(.page)`, so neighbouring pages exist. | Only the playing song's page may hold a video, and swiping must not recreate the controller (the layer's `.id` changes only when the playing song or its file does, section 6.6). |
| R18 | Hallelujah Flutter's unit tests pass (107 reported; not re-run for this file) but its feature has never run on a device, so its numbers have only been exercised against fakes (and the Swift port's against a local file on macOS). | If device checks on either app show drift, tune the constants in both together. |
| R19 | `AVURLAssetHTTPHeaderFieldsKey` is undocumented: it is in no SDK header and is only an exported symbol in `AVFoundation.tbd`. The engine already depends on it, so this adds no new kind of exposure. | If a future iOS release breaks it, audio and video break together. The alternative is an `AVAssetResourceLoaderDelegate`; do not build it speculatively. |
| R20 | `isPlaying` is `rate != 0`, and Apple's documentation says `rate` stays non-zero while the player waits for data (section 6.4). This is from the documentation, not from a test. | Harmless if it drops to 0 instead: the planner would ask for `play()` again, which is safe. Record what device check 9 shows. |
| R21 | There is no open timeout. An item that stays `.unknown` (a URL that hangs), or that reaches `.readyToPlay` with a 0x0 picture size (measured on macOS: `avi` with MPEG-4 or H.264, and HEVC tagged `hev1`; risk R1), keeps the cover for ever with no toast, and the first real look can lag readiness by up to 250 ms. Flutter behaves the same when `initialize()` hangs. | Do not add a timeout without asking the user. The audio is unaffected either way. |
| R22 | `progress.md` decision D13 asks for Liquid Glass on floating controls through `GlassSurface`; this plan uses a flat translucent capsule for parity with Flutter (section 6.12). | Ask the user before switching to `GlassSurface`. |

---

## 11. Rules and definition of done

- Branch `somesh` in `app-ios`; merge `main` into it first; no branch switching, merging, stashing or pushing unless the user asks; commit only if asked (commit messages end with the attribution line the session's system reminder gives).
- Hallelujah iOS and Hallelujah Flutter are the same product: any change to the shared behaviour (constants, rules above) goes to both, or is reported as a difference.
- Non-negotiables from `progress.md`: nothing hardcoded (tokens only; user text through the String Catalog; API paths through `Endpoint`); Liquid Glass through `GlassSurface` only; 120 fps; pure logic gets unit tests; previews in light and dark for every new view; no `TODO` without an item id.
- Done means: clean Debug and Release builds with zero new warnings, `make lint` and `make test` green, new tests for the policy, data and controller, the device checks in section 9 done, and a report that says plainly what was and was not verified.
- Keep scratch out of the repo and out of `project-h-workspace/`.

---

## 12. Start prompt (paste into a new session)

```
Continue the silent video mode work in Hallelujah iOS (folder app-ios).

1. In /Users/teja/company/projects/projectH/project-h-workspace/app-ios run `git branch --show-current`. It must print `somesh`. If it does not, tell me and stop; do not switch branches.
2. Read the plan: /Users/teja/company/projects/projectH/project-h-workspace/app-ios/Docs/SILENT_VIDEO_MODE_PLAN.md
   (if it is not there yet: /Users/teja/company/projects/projectH/project-h-workspace/app/docs/SILENT_VIDEO_MODE_IOS.md),
   then /Users/teja/company/projects/projectH/project-h-workspace/app-ios/progress.md and the Flutter reference
   /Users/teja/company/projects/projectH/project-h-workspace/app/docs/SILENT_VIDEO_MODE_PROGRESS.md (sections 4 and 5),
   then the Flutter tests in /Users/teja/company/projects/projectH/project-h-workspace/app/test/features/podcast/ (start with video_sync_test.dart, the specification for the Swift tests).
3. Implement section 7 of the plan step by step. Use the code-review-graph tools before grep. The audio engine must never be commanded by the video code; the video only reads the audio clock. Sections 6.2 to 6.5 hold Swift files that were compiled and run on macOS: paste them, do not retype them.
4. After each step: build, then run the tests for it. Do not commit or push unless I ask.
5. When done, report what was built, what was run, and what was not verified.
```
