# G-Hallelujah iOS — Native Rewrite Roadmap

A native SwiftUI rebuild of the existing Flutter app, feature for feature, with a
Liquid Glass interface and a hard focus on scroll/playback smoothness.

**Work through this file top to bottom, one task at a time.** Each task is sized to
be a single session's work. Do not start a task before its milestone's predecessors
are done — the ordering encodes real dependencies (nothing can play audio before the
audio engine exists; CarPlay cannot list playlists before the library does).

---

## How to use this file in a new chat

Paste this at the start of a fresh session:

> Read `progress.md` in this repo. We are on task **T##**. Implement only that task,
> following the Non-negotiables section, then tick it off and update the Status log.

Then, at the end of every task:

1. Tick the checkbox.
2. Add a line to the **Status log** at the bottom (date, task, what shipped, anything deferred).
3. Note any new decision in **Decisions** so the next session does not re-litigate it.

---

## Source of truth

The Flutter app is the specification. When behaviour is ambiguous, read the Dart, do
not invent.

| What | Where |
| --- | --- |
| Flutter app (reference implementation) | `/Users/teja/company/projects/projectH/app/ghallelujah` |
| Screens | `lib/views/**`, `lib/features/**`, `lib/sheets/**` |
| State / data | `lib/blocs/**`, `lib/river_pods/**`, `lib/providers/**` |
| Services | `lib/services/**` |
| API routes (all of them, in one file) | `lib/utils/end_points.dart` |
| Environment/host switching | `lib/utils/app_config.dart` |
| Song JSON contract | `SONG_RESPONSE_SHAPE.md` |
| Search API contract | `SEARCH_API.md` |
| Analytics payloads | `ANALYTICS_PAYLOAD.md` |
| Share / OG images | `SHARE_OG_IMAGES.md` |
| Existing CarPlay implementation (Swift, ~41k) | `ios/CarPlaySceneDelegate.swift` |
| Backend | `/Users/teja/company/projects/projectH/api/gs_nh_backend` |
| Postman collections | `/Users/teja/company/projects/projectH/*.postman_collection.json` |

---

## Decisions

Locked in. Revisit only with a reason.

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | SwiftUI + MVVM (`@Observable` view models) | Modern default; least ceremony for a large screen count |
| D2 | Single app target, layered folders (`Core` / `DesignSystem` / `Domain` / `Data` / `Features`) | What every iOS dev recognises; extract to SPM packages later if build times demand it |
| D3 | Minimum iOS **17.0** | `@Observable`, SwiftData, modern `NavigationStack` |
| D4 | Three environments: Development (localhost), Staging (QA), Production | Mirrors `AppConfig` in Flutter, which hardcodes this behind `isDebug = true` |
| D5 | Dark-first theme, gold accent `#FFC857` | Matches `lib/theme/colors.dart`; the Flutter app is dark-only |
| D6 | Config flows xcconfig → Info.plist → `AppConfiguration` | No host, key, or flag literal anywhere in Swift |
| D7 | Swift 6 language mode, strict concurrency `complete` | New codebase — cheaper now than retrofitted |

---

## Non-negotiables

Applied to **every** task. A task is not done if it violates one of these.

**Nothing hardcoded**
- Hosts, ports, keys, feature flags → `Config/*.xcconfig` → `Info.plist` → `AppConfiguration`.
- Colours, spacing, radii, typography, durations → design tokens. No `Color(hex:)`, no `.padding(16)`.
- User-facing text → String Catalog (`Localizable.xcstrings`). No string literals in views.
- API paths → `Endpoint` values in `Data/Endpoints`, never inline in a repository.

**Glass UI**
- Every raised surface (nav bar, tab bar, sheets, mini player, cards, overlays) goes through
  the `GlassSurface` primitive from the design system. No ad-hoc `.ultraThinMaterial`.
- On iOS 26+ it uses native Liquid Glass (`.glassEffect`, `GlassEffectContainer`);
  below that it falls back to the material + stroke + highlight recipe. One primitive,
  two implementations, decided in one place. **See Open question Q1.**

**Smoothness** — this is a music app; jank is a bug
- 120 fps target on ProMotion. Budget: 8 ms/frame.
- Lists are lazy, rows have stable identity, artwork is downsampled to its display size
  and prefetched ahead of scroll.
- Nothing blocking on the main actor: decoding, disk I/O, image work all off-main.
- No blur over scrolling content without a `GlassEffectContainer` / rasterised layer.
- Every list-bearing task is profiled in Instruments (Animation Hitches) before it is ticked.

**Definition of done** (per task)
- Builds clean for Debug + Release, zero new warnings.
- Unit tests for domain/data logic; SwiftUI previews for every new view, light and dark.
- No `TODO` left without a task number next to it.
- Checkbox ticked, Status log updated.

---

## Status legend

`[ ]` not started  `[~]` in progress  `[x]` done  `[!]` blocked (say why inline)

---

## M0 — Project foundation

- [~] **T01 — Xcode project, targets, schemes**
  `GHallelujah.xcodeproj` with app + unit test + UI test targets, synchronized file
  groups, and shared schemes for Development / Staging / Production.
  *Done:* all three schemes build and run on simulator.

- [~] **T02 — Build configuration and environments**
  xcconfig hierarchy (Base / Debug / Release / per-environment), Info.plist driven
  entirely by build settings, `AppConfiguration` reading it back with typed accessors
  and a `FeatureFlags` surface.
  *Done:* switching scheme changes bundle id, display name, and API host with zero code changes.

- [ ] **T03 — Dependency injection and composition root**
  Container + `@Injected`, registration in `AppEnvironment`, per-environment overrides,
  preview/test doubles.
  *Done:* a view model resolves a faked repository in a preview and a real one at runtime.

- [ ] **T04 — Logging and diagnostics**
  `AppLogger` over OSLog with categories and per-environment level; crash reporting
  behind a protocol (no vendor SDK in app code).
  *Done:* categories visible in Console.app; log level honours the environment.

- [ ] **T05 — Networking layer**
  `HTTPClient` on URLSession with `Endpoint`, typed `APIError`, JSON coding policy,
  retry with backoff (the Flutter `DioApi` retries 3× — match it), request/response logging.
  *Done:* a real endpoint round-trips against Staging in a unit test.

- [ ] **T06 — Session, tokens, auth interceptor**
  Keychain-backed token store, `Authorization` injection, single-flight refresh on 401
  (`/auth/token/refresh`), global logout on refresh failure.
  *Done:* forced 401 triggers exactly one refresh and replays the original request.

- [ ] **T07 — Persistence and caching**
  Pick and wire the local store (SwiftData vs GRDB — see Q2). Key-value store, disk cache
  for artwork, in-memory cache. Cache policy and eviction documented.
  *Done:* app relaunches with cached home feed and no network.

- [ ] **T08 — Analytics abstraction**
  `AnalyticsTracking` protocol, typed events, offline queue + batched sync
  (mirror `tracking_event_sync_service.dart` and `ANALYTICS_PAYLOAD.md`).
  *Done:* events survive a cold restart and flush when connectivity returns.

- [ ] **T09 — Tooling**
  SwiftLint, SwiftFormat, `Makefile` (bootstrap/lint/test/build), CI workflow, `.gitignore`.
  *Done:* `make lint test` is green from a clean clone.

## M1 — Design system and glass

- [ ] **T10 — Design tokens**
  Colour tokens in the asset catalog (done — 24 semantic tokens), typography scale,
  spacing, radii, elevation, motion curves, icon set. `Theme` injected via environment.
  *Done:* a token gallery preview renders every token in light and dark.

- [ ] **T11 — `GlassSurface` primitive**
  The single glass implementation: iOS 26 Liquid Glass, pre-26 fallback, variants
  (regular/clear/tinted), interactive state, and a container for grouped elements.
  *Done:* one preview shows every variant over a scrolling photo background at 120 fps.

- [ ] **T12 — Core components**
  Buttons, text fields (incl. OTP pin field), toggles, chips, sheets/drag handle,
  shimmer skeletons, empty / error / loading states, toasts and snackbars.
  *Done:* component gallery preview; each has a loading and disabled state.

- [ ] **T13 — Media components**
  Artwork view (downsampling, placeholder, CDN variant selection from `imageVariants`),
  marquee title, seek bar, waveform/progress, like button.
  *Done:* artwork view proven not to decode full-size images during scroll.

- [ ] **T14 — Motion and haptics**
  Shared transitions, matched-geometry player expansion, haptic vocabulary.
  *Done:* mini-player → full-player expansion runs without a dropped frame.

## M2 — App shell

- [ ] **T15 — Launch and bootstrap**
  Splash, remote settings fetch (`settings_service.dart` — CDN URL comes from here),
  App Check, App Tracking Transparency, force-upgrade gate.
  *Done:* cold start to first frame under 400 ms on an iPhone 12.

- [ ] **T16 — Navigation architecture**
  Typed routes, per-tab `NavigationStack`, sheet/full-screen presentation, and the
  "player-owned routes" rule from `lib/routes/routes.dart` (screens that must be popped
  when playback tears down).
  *Done:* stopping playback pops player-owned screens; no empty screens reachable.

- [ ] **T17 — Glass tab bar and mini-player dock**
  Floating glass tab bar with the mini player docked above it, and the visibility rules
  from `canShowBottomNavBar` / `canShowMusicPlayerBottom`.
  *Done:* both hide on exactly the routes the Flutter app hides them on.

- [ ] **T18 — Deep links and universal links**
  URL scheme + associated domains, route parsing, cold-start and warm-start handling
  (`deep_link_service.dart`).
  *Done:* every link type in the Flutter service opens the right screen from a cold start.

- [ ] **T19 — Connectivity and offline state**
  Reachability, offline banner, request queuing policy.
  *Done:* airplane mode shows cached content plus the banner, never a crash or spinner.

## M3 — Authentication

- [ ] **T20 — Auth domain and API**
  Entities, repository, use cases against the `/auth/**` routes in `end_points.dart`.
  *Done:* login/register/refresh/logout covered by tests against Staging.

- [ ] **T21 — Phone OTP (Firebase)**
  Country picker, phone validation, OTP entry, resend timer, autofill,
  `/auth/phone-auth/firebase` validation.
  *Done:* full phone signup and login on a real device with SMS autofill.

- [ ] **T22 — Email OTP**
  Send/verify/resend against `/auth/register/send-otp` and friends.
  *Done:* full email signup and login.

- [ ] **T23 — Google and Apple sign-in**
  `/auth/oauth/verify`. Sign in with Apple is mandatory for App Store review.
  *Done:* both providers create and resume a session.

- [ ] **T24 — Account setup and profile image**
  Profile fields, image picker, crop/compress, S3 upload (`s3_service.dart`).
  *Done:* avatar uploads and appears everywhere it should.

- [ ] **T25 — Content language selection**
  Language list, persistence, effect on feed and search.
  *Done:* changing languages changes the home feed.

- [ ] **T26 — Session lifecycle**
  Guest mode, auth-required gates, logout teardown (caches, downloads, player, CarPlay).
  *Done:* logout leaves no user data on disk.

## M4 — Content and home

- [ ] **T27 — Content domain models**
  `Song`, `Creator`, `Album`, `Playlist`, `Section`, `Paginated<T>` — every field in
  `SONG_RESPONSE_SHAPE.md`, DTOs separate from domain entities, mappers tested.
  *Done:* decoding tests pass against captured real responses for every endpoint.

- [ ] **T28 — Home feed**
  `GET /api/home` sections, carousels, section types, pull-to-refresh, cached-first load,
  shimmer placeholders.
  *Done:* feed scrolls at 120 fps with artwork loading; offline shows cache.

- [ ] **T29 — Section detail screens**
  See-all songs, see-all artists, album songs, company playlist songs, recent songs.
  *Done:* each paginates and matches the Flutter layout.

- [ ] **T30 — Creator profile**
  Creator page, their songs, follow/favourite.
  *Done:* follow state round-trips and is reflected in Library.

## M5 — Playback engine

The heart of the app. Do not rush this milestone.

- [ ] **T31 — Audio engine**
  `AVQueuePlayer`, `AVAudioSession` (playback category, interruptions, route changes),
  variant selection from `audioUrls` (low/standard/high by connectivity — see
  `SONG_RESPONSE_SHAPE.md`), signed-URL refresh, buffering and error recovery.
  *Done:* gapless-ish queue advance, survives a phone call and a route change.

- [ ] **T32 — Now Playing and remote commands**
  `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, lock screen, Control Centre, artwork.
  *Done:* lock-screen controls and scrubbing fully functional.

- [ ] **T33 — Queue model**
  Queue state, source tracking (`queue_source_service.dart`), shuffle, repeat modes,
  reorder, up-next.
  *Done:* queue source is correct for every entry point (home, search, playlist, CarPlay).

- [ ] **T34 — Mini player**
  Glass mini player with artwork, marquee title, play/pause, progress hairline, swipe actions.
  *Done:* never drops a frame while the list behind it scrolls.

- [ ] **T35 — Full player screen**
  Expanded glass player: artwork, seek bar, transport, like, download, share, queue,
  lyrics entry, output picker.
  *Done:* expansion is a single continuous animation from the mini player.

- [ ] **T36 — Lyrics**
  Lyrics/transcript view with scroll sync where timing exists.
  *Done:* matches `SongLyricsPage.dart`.

- [ ] **T37 — Queue screen**
  Reorderable up-next list.
  *Done:* drag-reorder at 120 fps.

- [ ] **T38 — Playback tracking**
  Play counts, progress persistence and resume (`playback_database_service.dart`,
  `playlist_progress_service.dart`), analytics events per `ANALYTICS_PAYLOAD.md`.
  *Done:* resume position survives a force-quit.

- [ ] **T39 — Audio output and AirPlay**
  Route picker, AirPlay, Bluetooth device names (`flutter_audio_output` equivalent).
  *Done:* output switching works from both mini and full player.

## M6 — Search

- [ ] **T40 — Universal search**
  `GET /api/search` per `SEARCH_API.md`: top result plus music / episodes / creators /
  playlists sections, debounced input, recent searches.
  *Done:* response shapes decoded exactly; debounce does not fire stale requests.

- [ ] **T41 — Filtered search and pagination**
  `filterType` tabs with independent page cursors (`musicPage`, `episodePage`, …).
  *Done:* infinite scroll per tab without duplicate or dropped pages.

- [ ] **T42 — Browse**
  Genre search, category songs, episodes.
  *Done:* parity with `lib/views/search/**`.

## M7 — Library, playlists, downloads

- [ ] **T43 — Library home**
  Tabs/sections for playlists, liked songs, downloads, artists, recents.
  *Done:* parity with `lib/views/library/library.dart`.

- [ ] **T44 — Favourites**
  Favourite songs and creators, optimistic toggles, grid views.
  *Done:* optimistic update reverts correctly on failure.

- [ ] **T45 — User playlists**
  Create / rename / delete, add & remove songs, reorder, add-to-playlist sheet,
  cover image.
  *Done:* full CRUD round-trips; reorder persists.

- [ ] **T46 — Download engine**
  Background `URLSession`, queue, progress, pause/resume/cancel, retry, storage
  accounting, delete-all. Replaces `flutter_downloader` + `download_isolate.dart`.
  *Done:* downloads complete with the app suspended and survive a force-quit.

- [ ] **T47 — Offline playback**
  Play from disk, offline library filtering, storage settings screen.
  *Done:* airplane mode plays downloaded songs end to end.

## M8 — CarPlay

Depends on M5 (playback) and M7 (library/downloads). Port `ios/CarPlaySceneDelegate.swift`
natively — it is already Swift and is the best available spec.

- [ ] **T48 — CarPlay scene setup**
  `com.apple.developer.carplay-audio` entitlement, `UIApplicationSceneManifest` with the
  template application scene, `CPTemplateApplicationSceneDelegate`, connect/disconnect
  lifecycle alongside the SwiftUI app lifecycle.
  *Done:* app appears and launches in the CarPlay simulator.

- [ ] **T49 — Tab bar and tabs**
  `CPTabBarTemplate` with **Home, Library, Recents, Search**, each lazily loaded with a
  loading template while data arrives.
  *Done:* all four tabs populate; no blocking main-thread work on connect.

- [ ] **T50 — List templates and artwork**
  `CPListTemplate` / `CPListSection` / `CPListItem` / `CPListImageRowItem`, circular
  artwork, disk-cached and correctly sized images, the 3-image row cards used on Home.
  *Done:* artwork renders from cache without a network round-trip on every scroll.

- [ ] **T51 — Pushed templates**
  Liked Songs, Downloads, all playlists, playlist songs, company playlists, creator
  songs, home "see all", search results — one function per `push*` in the Dart/Swift original.
  *Done:* every push target from the existing delegate exists and plays.

- [ ] **T52 — Now Playing and handoff**
  `CPNowPlayingTemplate`, now-playing indicator on list rows, progress updates, remote
  commands, and state shared with the phone UI in both directions.
  *Done:* start on phone → continue in car → control from car, with no duplicate players.

- [ ] **T53 — CarPlay QA**
  Auth-required guards (`pushGuarded`), offline behaviour, template-depth limit (5),
  list item count limits, connect while playing / while logged out.
  *Done:* QA matrix in `Docs/CARPLAY.md` fully passed.

## M9 — Read (Bible)

- [ ] **T54 — Reader**
  Books, chapters, verses, font size, themes, bookmarks (`lib/views/read/**`).
  *Done:* chapter navigation is instant on cached books.

- [ ] **T55 — Offline bible and search**
  Book download from CDN with backend fallback (`bible_offline_service.dart`),
  full-text search (`bible_search_service.dart`).
  *Done:* search works fully offline.

- [ ] **T56 — Verse of the day**
  Verse of day, history, comments, insights, share card.
  *Done:* parity with the verse-of-day blocs.

- [ ] **T57 — Read aloud**
  TTS playback of passages, coordinated with the music player's audio session.
  *Done:* starting TTS pauses music and restores it afterwards.

## M10 — AI assistant

- [ ] **T58 — AI chat**
  Chat UI, markdown rendering, streaming responses, conversation history, suggestions.
  *Done:* parity with `ai_chat_page.dart`.

- [ ] **T59 — Voice conversation**
  Speech recognition, VAD, socket.io `/voice` namespace, TTS playback, the voice overlay,
  barge-in. Port `lib/features/voice/**` (read `VOICE.md` first).
  *Done:* a full spoken turn-taking conversation works on device.

- [ ] **T60 — AI history and entry points**
  History list, resume a conversation, entry points from player and reader.
  *Done:* parity with `lib/views/ai/**`.

## M11 — Monetization

- [ ] **T61 — StoreKit 2 subscriptions**
  Plans screen, purchase, restore, entitlement state, receipt validation with the backend.
  *Done:* sandbox purchase and restore both grant premium.

- [ ] **T62 — Razorpay**
  The non-StoreKit payment path used in the Flutter app, where it is allowed to apply.
  *Done:* test-mode payment completes and unlocks.

- [ ] **T63 — Family plan**
  Manage family members (`ManageFamilyMembersPage.dart`).
  *Done:* add/remove member round-trips.

- [ ] **T64 — Tips**
  Tip products and tip sheet.
  *Done:* tip purchase completes.

- [ ] **T65 — Premium gating**
  One gating rule set applied across player, downloads, AI, and ads.
  *Done:* a single source of truth decides every gate; no scattered `isPremium` checks.

## M12 — Engagement and platform

- [ ] **T66 — Notifications**
  APNs + FCM, rich notifications, notification service extension, deep-linked taps,
  local notifications, per-category preferences (`notification_prefs_service.dart`).
  *Done:* push opens the right screen from a cold start.

- [ ] **T67 — Realtime**
  socket.io connection, event handling (`realtime_event_handler.dart`), reconnection.
  *Done:* live events update the UI without a refresh.

- [ ] **T68 — Sharing**
  Share sheet, OG image cards (`SHARE_OG_IMAGES.md`), direct share to social apps,
  save to photos.
  *Done:* every share target from the Flutter app works.

- [ ] **T69 — Ads**
  Ad break screen and pacing, preview mode behind the `FEATURE_ADS_PREVIEW_MODE` flag.
  *Done:* ad cadence matches the Flutter rules; premium users never see one.

- [ ] **T70 — Profile and settings**
  Profile page, settings, notification settings, playback quality, storage, about.
  *Done:* parity with `lib/views/profile/**` and `settings_screen.dart`.

- [ ] **T71 — Support**
  Help dashboard, FAQs, feedback (with email fallback), account deletion flow.
  *Done:* account deletion completes and signs the user out.

## M13 — Quality and release

- [ ] **T72 — Performance pass**
  Instruments across home, search, library, player, CarPlay. Cold start, hitch rate,
  memory ceiling, battery. Fix what the trace shows, not what you suspect.
  *Done:* zero hitches scrolling home/search/library; documented numbers in `Docs/PERFORMANCE.md`.

- [ ] **T73 — Accessibility**
  VoiceOver across all flows, Dynamic Type, contrast, reduce-motion and
  reduce-transparency paths for the glass surfaces.
  *Done:* full VoiceOver pass on the core flows; glass degrades correctly.

- [ ] **T74 — Localization**
  Every string in the catalog, the languages the Flutter app ships, RTL audit.
  *Done:* no hardcoded user-facing string remains; pseudo-locale pass is clean.

- [ ] **T75 — Tests and CI**
  Unit tests for domain/data, snapshot tests for the design system, UI tests for the
  critical paths (login, play, download, purchase), CI on every PR.
  *Done:* CI green; coverage reported.

- [ ] **T76 — Release**
  Privacy manifest, App Store metadata, TestFlight pipeline, crash monitoring,
  staged rollout plan, migration notes for existing Flutter users (sessions, downloads).
  *Done:* a build is on TestFlight from CI.

---

## Open questions

Answer before the task that depends on it.

- **Q1 (blocks T11) — Liquid Glass vs iOS 17 floor.** Native Liquid Glass is iOS 26+.
  At a 17.0 floor, most users get the fallback. Options: (a) keep 17.0 and ship both paths
  behind `GlassSurface`, (b) raise the floor to 26.0 for real Liquid Glass everywhere.
  *Recommendation:* (a) — one primitive, two implementations, and the floor can be raised
  later without touching call sites.
- **Q2 (blocks T07) — Local store.** Flutter uses Realm + Hive + sqflite. Native options:
  SwiftData (iOS 17, least code) or GRDB (predictable, better for large bible/song tables).
  *Recommendation:* GRDB for bible/library tables, plain files for downloads.
- **Q3 (blocks T61) — Razorpay on iOS.** Confirm which purchases legitimately go through
  Razorpay vs StoreKit, since App Review requires StoreKit for digital content.
- **Q4 (blocks T76) — Migration.** Do existing Flutter users keep their session and
  downloads on upgrade, or is a re-login acceptable?
- **Q5 (blocks T15) — Firebase.** Which Firebase products carry over (Auth, Messaging,
  Analytics, Crashlytics, App Check), and are any being dropped?

---

## Already on disk

Written during the scaffolding pass, before the roadmap-only scope was set. Keep or
delete — if deleted, T01/T02 start from scratch.

```
App/                  full layered folder tree (Core, DesignSystem, Domain, Data,
                      Features × 12, Navigation, Platform, Resources) — folders only
Config/               complete xcconfig hierarchy: Base / Debug / Release,
                      App / Tests / UITests, Development / Staging / Production,
                      composed configurations, Secrets template
App/Resources/Assets.xcassets/Colors/   24 semantic colour tokens, light + dark
Docs/ Scripts/ Tests/ UITests/          empty
GHallelujah.xcodeproj/                  empty — not generated yet
```

No Swift source and no Xcode project exist yet. **T01 and T02 are marked `[~]`, not `[x]`.**

---

## Status log

| Date | Task | Notes |
| --- | --- | --- |
| 2026-09-16 | — | Roadmap created. Folder tree, xcconfig hierarchy, and colour tokens scaffolded; Xcode project not yet generated. |
