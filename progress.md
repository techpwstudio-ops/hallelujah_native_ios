# G-Hallelujah iOS — Pending Work

Native SwiftUI rebuild of the Flutter app (`../ghallelujah`), feature for feature. Paths in this
file are relative to this repo (`g-hallelujah-ios/`); all five repos sit side by side in `project-h-workspace/`.
**All 76 roadmap tasks (T01–T76) are written and the app target compiles**
(Development + Production schemes, 2026-10-15; the 2026-10-27 edits below compile on the Development scheme — the Production scheme has not been rebuilt since — and none of them has been run on a device).
What is left is verification, known gaps, and
manual/infra steps — listed below. Finished work was removed from this file on 2026-10-27;
the full old roadmap + status log is in git history (`git show HEAD:progress.md` until this
rewrite is committed, afterwards `git log -p -- progress.md`).

## How to use this file in a new chat

> Read `progress.md`. We are on item **<id>**. Do only that item, following Non-negotiables,
> then delete it from this file (or tick it) and add any new decision to **Decisions**.

Work is **UNVERIFIED** until it has been built *and* run. "Compiled" is not "works".

---

## Source of truth

The Flutter app is the specification. When behaviour is ambiguous, read the Dart, do not invent.

| What | Where |
| --- | --- |
| Flutter app | `../ghallelujah` |
| Screens / state / services | `lib/views/**`, `lib/features/**`, `lib/sheets/**`, `lib/blocs/**`, `lib/river_pods/**`, `lib/services/**` |
| API routes | `lib/utils/end_points.dart` · host switching `lib/utils/app_config.dart` |
| Contracts | `../ghallelujah/`: `SONG_RESPONSE_SHAPE.md`, `SEARCH_API.md`, `ANALYTICS_PAYLOAD.md`, `SHARE_OG_IMAGES.md` · `../gs_nh_backend/docs/HOME_V2_API.md` |
| Existing CarPlay (Swift) | `../ghallelujah/ios/CarPlaySceneDelegate.swift` |
| Backend | `../gs_nh_backend` |
| Postman | `../../*.postman_collection.json` (one level above the workspace, in `projectH/`) |
| Docs in this repo | `Docs/PERFORMANCE.md`, `ACCESSIBILITY.md`, `CARPLAY.md`, `QA.md`, `RELEASE.md`, `XCODE_CLOUD.md` |

---

## Decisions (locked — revisit only with a reason)

| # | Decision |
| --- | --- |
| D1 | SwiftUI + MVVM (`@Observable` view models) |
| D2 | Single app target, layered folders `Core / DesignSystem / Domain / Data / Features` |
| D3 | Minimum iOS **17.0**. `GlassSurface` hides two implementations behind one call site: real Liquid Glass on iOS 26+, material fallback below (the Flutter app does the same split) |
| D4 | Three environments: Development (localhost), Staging, Production |
| D5 | Dark-first, gold accent `#FFC857` |
| D6 | Config flows xcconfig → Info.plist → `AppConfiguration`. No host/key/flag literal in Swift |
| D7 | Swift 6 language mode, strict concurrency `complete` |
| D8 | `project.yml` (XcodeGen) is the source of truth for `Hallelujah.xcodeproj`; edit it, then `xcodegen generate`. `xcodegen` is at `~/.local/bin/xcodegen` (GitHub release; Homebrew installs are blocked on this machine by untrusted taps) |
| D9 | DI composition root is `AppComposition`; `AppEnvironment` is the dev/staging/prod enum |
| D12 | **Exact parity with Flutter, everywhere** — flow, layout, spacing, colours, type, copy, assets. Dart under `lib/views/**`, `lib/widgets/**`, `lib/sheets/**`, `lib/theme/**`, `lib/dimens/**` is the spec; Flutter wins over native idiom. Supersedes the old D10 (splash/auth only) and D11 (system font instead of Flutter's pinned "Helvetica Neue") |
| D13 | **Liquid Glass wherever natural on iOS 26** (layout/copy parity still holds): system `TabView` tab bar, mini player in `tabViewBottomAccessory`, search bars / floating controls / chips / capsule buttons / sheets / player controls via `GlassSurface`/`glassEffect` in `GlassEffectContainer`. Material fallback below iOS 26 |
| D14 | Local store is **GRDB** (each feature adds its own migration). Downloads are plain files under Application Support, not GRDB, not `Library/Caches` |
| D15 | **No playlist reorder.** Flutter has none and the backend `SongUserPlaylist` has no position column. Match Flutter |
| D16 | **Razorpay is out of scope on iOS** (Android-only in Flutter). Digital subscriptions go through StoreKit |
| D17 | Existing Flutter users keep their session on upgrade, and native → Flutter updates keep it too, via a shared Keychain record (service `com.hallelujah.user.session-handoff`, account `session`). Implemented (`SessionHandoff`, `LegacyFlutterSessionMigration`, `FlutterHiveBox`); not yet device-tested — see A12 |
| D18 | Firebase: Auth, App Check, FCM, Crashlytics, Analytics all carry over. Firebase Analytics runs alongside the app's own backend analytics pipeline, not instead of it |
| D19 | **No resume-on-launch.** The shipped Flutter app has `RestoreLastSongEvent` commented out (`launch_app.dart:241-246`), so per D12 native doesn't restore the last song either. `AudioEngine` still writes `playback.lastSongID` / `playback.lastSongPositionMS` like Dart's `audio_service.dart` does; nothing reads them |
| D20 | **Responsive iPad / foldable / Mac layout, width-driven (amends D12 above phone width).** D12 parity is defined at phone width (≤ 440pt); above it the app adapts to the live window width, never to the device idiom, size class or `UIScreen`. Every rule lives in `App/DesignSystem/Layout/AdaptiveLayout.swift` and returns the phone value unchanged at phone width: text/forms/settings/chat in a 640pt centred column (`readableContentWidth()`), single-purpose forms 480pt, media columns 560pt; phone grids gain columns (`AdaptiveLayout.columns`); the full player goes side by side in a wide landscape window. Mac runs the iPad build (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES`), not Catalyst, with a one-phone minimum window. QA matrix in `Docs/QA.md`. **Not built or run yet.** Open: `UIApplicationSupportsMultipleScenes` is on, so a second iPad/Mac window runs a second app shell sharing the `DeepLinkService` / `PushNotificationRouter` singletons; DeviceCheck App Check on Mac unconfirmed; the iPadOS 18+/Mac top tab bar may cover Home/AI/Bible headers; no pointer hover or keyboard shortcuts |

---

## Non-negotiables

**Nothing hardcoded**
- Hosts, ports, keys, flags → `Config/*.xcconfig` → `Info.plist` → `AppConfiguration`.
- Colours, spacing, radii, typography, durations → design tokens. No `Color(hex:)`, no `.padding(16)`.
- User-facing text → String Catalog (`Localizable.xcstrings`).
- API paths → `Endpoint` values in `Data/Endpoints`, never inline in a repository.

**Glass UI** — every raised surface goes through `GlassSurface`; no ad-hoc `.ultraThinMaterial`.

**Smoothness** — jank is a bug. 120 fps target (8 ms/frame). Lazy lists, stable row identity, artwork
downsampled and prefetched, nothing blocking on the main actor, no blur over scrolling content without
a `GlassEffectContainer`. List-bearing work is profiled in Instruments (Animation Hitches).

**Definition of done** — builds clean Debug + Release with zero new warnings; unit tests for
domain/data logic; previews (light + dark) for new views; no `TODO` without a task/item id.

---

## Pending

Legend: `[ ]` open · `[~]` in progress · `[!]` blocked (say why).
**Section C3 and D come from the old status log and were not all re-checked against the code** —
before starting one, grep first; it may already be fixed. C1 and C2 were checked in code on 2026-10-27; C1's fixes compile (Development scheme) but have not been run.

### A. Verify at runtime (needs a Mac / simulator / device)

Everything below compiles but has never been run. Tick only after you have seen it work.

- [ ] **A1 Test targets** — `HallelujahTests` (unit) now compiles and passes locally: `make test`, Development scheme, iPhone 17 Pro simulator, 379 tests, 2026-10-27. Getting there took fixes to tests that had never been compiled or run (missing `Foundation` imports, main-actor isolation, a raw-string delimiter, `NSLock` in an async context), a `AppConfiguration.staging` fixture missing the Firebase/Google keys (every `.staging` test trapped and killed the whole test process), and four stale expectations (`ReconnectRetry`, company-ad `campaignKey`, a Hindi UTF-16 offset, the bundle-id suffix). Still open: `HallelujahUITests` has not been compiled or run, the CI `Test` step has never run the suites, and there is no Production-scheme test run. Many features have no tests (T21–T22 auth VMs, T27 DTO decoding against captured responses, T46/T47 downloads, T54–T71 features, `LegacyFlutterSessionMigration`, `FlutterHiveBox`, CarPlay controller/provider, `VoiceOverlayView`, family-plan VMs).
- [ ] **A2 Performance (T72)** — Instruments pass per `Docs/PERFORMANCE.md`; nothing has been measured. Targets: cold start < 400 ms on iPhone 12, zero hitches on home/search/library, artwork never decoded full-size during scroll (`ArtworkImageCache`), mini→full player expansion without a dropped frame, queue drag-reorder at 120 fps, marquee + glass render cost.
- [ ] **A3 Accessibility (T73)** — VoiceOver across core flows per `Docs/ACCESSIBILITY.md` (unrun), Dynamic Type, contrast, reduce-motion / reduce-transparency for glass.
- [ ] **A4 CarPlay** — run in the CarPlay simulator; the `Docs/CARPLAY.md` QA matrix is entirely unchecked. Open items: recent *song* cards resolve by title search in `CarPlayContentProvider` (replace with `SongRepository` `GET /song/:id`); Downloads/Playlists don't live-refresh; auth guard is only a signed-in check on connect.
- [ ] **A5 iOS 26 visuals** — system `TabView` tab bar + mini-player inset, `GlassSurface` helpers against the iOS 26 SDK, `appNavigationBarBackground(_:isVisible:)` (decide: is the scroll-edge blur over the black page wanted?), `AppLanguageStore` runtime locale override, and template-vs-original rendering of the 72 SVGs in `Assets.xcassets/Icons` (`IconToken.assetName`, `IconView`, `GlyphImage`).
- [ ] **A6 Player** — lock-screen controls + scrubbing; phone-call interruption and route change; Now Playing re-push after foreground resume (iOS clears it during sleep — check `NowPlayingCoordinator`); iOS 18 zoom transition across the `.fullScreenCover` boundary (`matchedTransitionSource` / `.navigationTransition(.zoom)`); `PlayerArtworkPager` (`.aspectRatio` on a `.page` `TabView`, computed `Binding<String?>` echo-avoidance); swipe-to-skip commit uses `predictedEndTranslation` at 88 pt in place of Dart's 220 px/s velocity — tune on real touch; lyrics scroll-sync smoothness (`.easeOut` vs Dart `easeOutCubic`, 2 % edge fade); AirPlay glyph 22×22 in `MiniPlayerDockView.contentRow` (legibility, hit-target vs play button and the pill's `.onTapGesture`); queue `IndexSet→(old,new)` conversion and always-on drag handles.
- [ ] **A7 Auth on device** — phone OTP incl. SMS autofill; email OTP; Google + Apple sign-in (Staging blocked by A15/Q7; Production awaiting a retry with real `Config/Secrets.xcconfig`); account setup (`POST /users/profile/save`, DOB format `yyyy-MM-dd'T'HH:mm:ss.SSS` unconfirmed against the server); language save (`POST /user/save/languages`) changing the home feed; mid-session refresh failure → `SignOutSignal` → `SplashViewModel.handleSignedOut()`; cold-start deep link / universal link (`pendingURL` buffering race).
- [ ] **A8 Endpoints never hit** — `/auth/otp/send|resend|verify`, `/users/me`, `/user/logout`, `/premium/subscription/*` (5 routes) + `/premium/subscription/cancel`, `POST /upload/generate/presigned` + S3 PUT, `/ads/feedback`, `/ads/reaction`, `GET /song/:id`, `POST /song/:id/report`, `GET /library/items/ids`, `POST /library/items/:type/:id/toggle`, `GET /ai/messages/:id/share`, `GET /offerings` + `createTipOrder`, `/playlist/:id/songs`, `/company-playlist/:id/songs`. Also confirm: the server returns `kind:"company"` when `includeCompanyAds=true`; the highlight-row contract (native sends `{index,color}`, Flutter sends `{index,id,color}`); `gs_nh_backend` actually has the tip routes.
- [ ] **A9 Downloads / offline** — background `URLSession`, relaunch reconciliation, offline playback. **Known race (deliberately unhardened):** a background `didFinishDownloadingTo` can arrive before `reconcileWithExistingTasks()` registers the filename in `DownloadSessionDelegate.pending`, losing one completed download (self-heals to a retryable `.failed`). Proper fix: derive `pending` synchronously from the loaded catalog's `urlSessionTaskIdentifier`/`localFileName` pairs at delegate construction. Needs a device to validate.
- [ ] **A10 Purchases** — StoreKit sandbox purchase + restore; tip consumables; family plan add/remove; premium gating. Needs real App Store Connect products (no `.storekit` file; product ids come from backend `providerPlanId`).
- [ ] **A11 Platform extras** — `SleepTimerController` firing with the phone locked (+ player dismiss, toast, premium redirect to plans); Siri `INPlayMediaIntent` → `SiriPlayService`; rich-push image attach (`NotificationServiceExtension`); push tap opens the right screen from a cold start; `Scripts/localization_audit.py --catalog` + re-translate after the first build.
- [ ] **A12 Flutter → native migration (D17)** — install the App Store Flutter 4.0.2 build, update to the TestFlight native build, confirm the user stays signed in; then test native → Flutter. Also see the Q4 items in section D.
- [ ] **A13 Release (T76)** — nothing has been uploaded to TestFlight. `testflight.yml` is manual; `Docs/RELEASE.md` is unexercised. Needs: a build on TestFlight from CI, privacy manifest + App Store metadata review, crash monitoring, staged rollout plan.

### B. Manual / infra steps (a human has to do these)

- [ ] **B1 Secrets** — real `HALLELUJAH_API_SECRET`, `HALLELUJAH_OTP_SECRET_1`, `HALLELUJAH_OTP_SECRET_2` in `Config/Secrets.xcconfig` (gitignored; template `Secrets.xcconfig.template`) for Production.
- [ ] **B2 Universal links** — host `apple-app-site-association` on `hallelujah.today`, `qa.hallelujah.today`, `qa.link.hallelujah.today`, `link.hallelujah.today`. Add the Google and Facebook reversed-client-id URL schemes from Flutter's `ios/Runner/Info.plist` to `CFBundleURLTypes` if not already there.
- [ ] **B3 Apple portal** — approval of the `com.apple.developer.carplay-audio` provisioning profile; Siri capability on the App ID; a provisioning profile per extension bundle id (`NotificationServiceExtension`, `SiriIntentsExtension`); make sure XcodeGen generates the extension targets in CI.
- [ ] **B4 App Store Connect** — subscription products, tip consumables (the tip button hides when the store returns no offerings).
- [ ] **B5 Translations** — hi / te / ta / kn / ml are machine translations; need native-speaker review.

### C. Known bugs and gaps

**C1. Fixed 2026-10-27 — compiles (Development scheme), not run on a device (see A-section)**
- Stale buffered deep link: `DeepLinkService.discardPendingLink()` is called from the `onLogout` closure in `AppComposition`; the `TODO(T21-24 audit finding)` is gone.
- Toasts outside the signed-in shell: `.toastOverlay()` is now applied once in `RootView`, so sign-in / email OTP / account setup toasts and `HTTPClient`'s "No internet connection" toast render. (`AppShellView` keeps its own overlay for sheets.)
- Sign-out now clears `PlaylistProgressStore` (Dart: `PlaylistProgressService.instance.clear()`).
- `OTPField` focus border is Dart's exact blue (`AuthColors.focusedBorder`, passed in as `focusedBorderColor`) instead of the purple `statusInfo` token.
- One shared `Song.artistLine` (`" • "` join) replaces the copies in `AppBottomDock`, `FullPlayerView` and `NowPlayingCoordinator` (CarPlay keeps its own `", "` variant on purpose).
- Dedicated `LogCategory.aiChat`; the AI view models, views and `AIChatStreamingClient` use it.

**C2. Checked and found fixed — don't redo:** `.creatorSongs` route is wired; `sanitized()` helper exists in `HomeDTOs.swift`; Settings is reachable from `HomeHeaderView`; `ReaderViewModel` retries when `currentBook == nil`; `aps-environment`, carplay, siri entitlements and both extension targets exist; mini player has a favourite toggle; tap-to-play calls `QueueController` from Home / Search / Library / Creator / Genre screens; `Config/Secrets.xcconfig` exists locally; `build/` is gitignored. Also (checked 2026-10-27): AI chat pagination is cursor-based end to end (`Paginated.nextCursor` ← `AICursorPageDTO` → `loadMore()`); `OTPView` swipe-back needs nothing (`.navigationBarBackButtonHidden(true)` blocks it, as Dart's `PopScope(canPop: false)` does on iOS); `Typography.fontFamily` is "HelveticaNeue"; `NoNetworkBanner` is mounted in `HomeView`; deep-link 404 / malformed-payload toasts exist; `HomeFeedCache` is cleared by `SessionTeardown`; resume-on-launch is intentionally not built (D19). Not needed: Dart's `_stringOrEncodedList` (array→string fallback for `writers` / `featuredArtists` / `copyrightOwners`) — they are Prisma `String?` columns validated with `Joi.string()`, so the backend never sends a list.

**C3. From the old status log, not re-checked — verify then fix**

*Auth / account*
- [ ] Phone validation is a coarse `(4...15).contains(digits.count)`; no `flutter_libphonenumber` equivalent.
- [ ] Not ported: `_checkIfTester` 405 "flash screen" branch; the `refer` field on social auth + OTP request (needs a `DeepLinkService` query for the cached initial/latest link); OTP request `deviceId` / `membership`.
- [ ] Logout teardown — still unconfirmed after the 2026-10-27 pass (cleared today: tokens, user, membership, library set, related content, queue/player, downloads, realtime socket, Bible pending annotations, playlist visibility overrides, home feed cache, `AppDataSync`, artwork disk cache, playlist progress, and — new — the analytics queue): AI chat state, favourites state, `NetworkStatusStore`. `RecentSearchStore` is deliberately kept (its doc comment explains why). Then confirm nothing else user-specific survives on disk.
  - Analytics flush (2026-10-27, unit-tested only): `RemoteAuthRepository.logout(reason:)` runs `prepareForSignOut` first — ends the playback analytics session, then `AnalyticsTracking.flush()` — before the logout call and before `session.logout()` clears the token, so the upload is authenticated (wired in `AppComposition`; `RemoteAuthRepositoryLogoutTests`). Not covered, as in Dart: account deletion and a server-refused session have no valid token to upload with, so that queue stays on disk for the next sign-in. Never seen working on a device.
- [ ] `AccountDeletionView` biometric gate (`LAContext`, `.deviceOwnerAuthentication`) **fails open** — any inability to check passes through; only an explicit user rejection blocks. Faithful to Dart but deletion is irreversible → security review before shipping.
- [ ] `HelpView` is a flat list; Dart has a 3-tab help dashboard.

*Home / content / search*
- [ ] Home rails per `viewType` render as plain horizontal scrolls: `trending` overlapping-card carousel, `companyPlaylists` / `recommended` two-column grids, `singleCompanyPlaylist` hero card, `similarPlaylist` seed-row header. `podcasts` falls into `SectionContent.unsupported`; confirm `verseOfDay` is wired now that Read exists. `HomeFeedCache` covers first paint only.
- [ ] Tab roots / `AppRoute` destinations in `AppShellView` that still fall to `EmptyStateView(title: route.placeholderTitle)` — grep which routes remain.
- [ ] Bottom safe-area inset under the floating dock for scrollable content (`Spacing.tabBarHeight` + `Spacing.dockBottomInset` + mini-player height when visible).
- [ ] Creator profile: creator-playlist `type` is `"music"` in Dart's `PlaylistListItem` but `"album"`/`"season"` elsewhere natively (`CreatorPlaylistRow` works around it); `AddToLibraryButton` not yet on the `CreatorProfileView` header (only `PlaylistDetailView` uses it); `.songMenu(...)` modifier confirm on `QueueSongRow`, `HomeSongCardView`, user-playlist detail rows.
- [ ] Section/Playlist detail screens are structural — Dart's per-screen header chrome isn't reproduced. Promote `CreatorSongRow` from `App/Features/CreatorProfile/Components/` into a shared DesignSystem location.
- [ ] Select-mode search: `.contentSearch` dispatch in `AppShellView` ignores `userPlaylistID` / `tags` / `checkedContent` / `isSelect`; `AddSongsToPlaylistView` is music-only vs Dart's multi-tab `content_search_page.dart` `isSelect` mode.
- [ ] "More" (add to queue) omitted on genre / playlist / album / season / creator screens — needs a `QueueSourceService.fetchSongIds` equivalent.
- [ ] User playlists: confirm visibility toggle, follow/unfollow, share, add-to-queue (some landed in the 2026-10-16 parity pass); `userPlaylistShareLink` / `verseOfDayShareLink` callers.

*Player / queue / analytics*
- [ ] Not built: add-whole-container-to-queue (`AddSourceToQueueEvent`, `lib/models/queue_source.dart`) and play-next-single (`AddToQueueEvent`); auto hand-off to related content at a repeat-off queue's end (`_continueWithRelatedContent`) + the `QueueContinuity` history stack; Dart `_backfillArtistIfMissing` (detail re-fetch for thin artist metadata). These need a recommendation-fetch backend call that doesn't exist natively.
- [ ] Full player: creator meta / credits / description / related-content rail; `PlayerArtworkPager` overscroll-past-edge skip (>48 pt past first/last page; `TabView(.page)` has no rubber-band hook); Download button (Dart puts it behind "…"); Share (`GET /song/:id/share` OG card).
- [ ] Lyrics: no multi-language transcript selection (Dart picks `firstWhere(language == userLang, orElse: first)`, `lyrics_ui.dart:21-25`; native `Song.transcripts` is already flattened).
- [ ] Analytics: `recordLoopRestart` for repeat-ONE isn't wired (restart is internal to `AudioEngine`'s same-song ahead window); `syncToRecentlyPlayedSongApi` (Home "Continue Your Journey" rail) not ported; `device` fields left `nil` (`device_id` server-assigned at auth — no native flow persists it; `plan_id`/`plan_name` need the `Membership` entity); `review_prompt_requested` only logged (no Firebase Analytics call site); review-prompt state is in `UserDefaults` (Flutter uses the keychain, which survives reinstall).
- [ ] `RealtimeEventBus` `verseOfDay*` and `premium*` events have no consumer.
- [ ] Marquee easing is a single `.easeInOut` instead of the Marquee package's separate 400 ms accel/decel ramps; `Motion.swift` spring constants are ungrounded guesses.
- [ ] `FeatureFlags.carPlayEnabled` — decide whether `CarPlaySceneDelegate` / `CarPlayController` should consult it.

*Reader / AI / monetization / ads*
- [ ] AI: attachments / image upload (S3 presigned pipeline exists now — wire it), a Markdown SPM package, a Flutter-style `AiReplyOutcome` broadcast stream; "Ask Emet" `selectedText` is always empty at the only call site (SwiftUI `.contextMenu` has no selection range) and a `VerseInsightTarget.fromVerseOfDay` factory + verse-of-day options-sheet wiring is owed.
- [ ] Subscriptions: GOOGLE-provider "manage subscription" (no Play Store URL); structured `description.benefits` checklist (`SubscriptionPlan.description` is a flat string); profile/settings lack Manage Subscription, Family, Verse-of-Day toggle, premium banner — confirm now that T61–T63 exist.
- [ ] Family plan: invite-recipient accept/decline screen not built; `InviteTile` avatar is a raw `Image(systemName: "person")` (no `IconToken` case).
- [ ] Ads: exact `Retry-After` backoff (fixed 60 s — `HTTPResponse` carries no headers); two-back-press ad-break escape hatch; lingering companion banner; Home/dashboard banner placements; Home rail/banner ads and player ad surfaces were "in flight" with no outcome logged; confirm `screen` and `deeplink` CTAs work via `openAdAction`.
- [ ] Profile: photo upload (confirm uses the presigned pipeline); `ContentLanguageView` reuses `LanguageViewModel`.

*Build / CI / tooling*
- [ ] SwiftLint + SwiftFormat aren't SPM build-tool plugins (identifiers unconfirmed); `make lint` calls the CLIs. 255 pre-existing SwiftLint violations → CI lint was made **non-blocking**; fix them and re-enable.
- [ ] T75 still owes: UI tests for login / play / download / purchase, snapshot tests for the design system, coverage reporting.
- [ ] Production `secure` header depends on `HALLELUJAH_API_SECRET` (B1).

### D. Open decisions

- [ ] **Q6 Microsoft Clarity** — Flutter wraps the whole app in `ClarityWidget` (`lib/main.dart`, `projectId: "xmuqz9leqv"`, `clarity_flutter ^1.9.0`). Neither ported nor dropped. Decide whether the native app carries this vendor over.
- [ ] **Q7 Staging Firebase / Google config** — Flutter has only `-dev`/`-prod` Firebase plists; native has three environments. Staging's Firebase + Google OAuth keys point at the *production* project (`hallelujah-49b89`) as an assumption, but the bundle id `com.hallelujah.user.staging` is registered in neither Firebase project, so Firebase / Google Sign-In / push will likely fail on Staging builds. Register it (probably under Prod) or create a Staging Firebase project; then set `AppConfiguration.firebase` / `googleServerClientID`.
- [ ] **Q8 Splash vs Flutter** — Native `SplashView.swift` claims a two-stage opacity/scale entrance ported from Flutter, but `lib/views/launch/flash.dart` (`FlashScreen`) is just `Scaffold(body: Center(child: CircularProgressIndicator()))` — no logo, no animation, `_minSplashDuration` 0 s (the static logo comes from the native `LaunchScreen.storyboard`, 150×150 pt). Per D12, mirror `FlashScreen` exactly: plain spinner, no logo, no animation. First resolve what `backgroundColor` and `Theme.of(context).colorScheme.primary` resolve to in Dart, and whether this project's launch screen (`UILaunchScreen`) already shows the static logo.
- [ ] **Q4 remainder — what else to migrate from Flutter's Hive boxes** — downloaded files, audio quality, reader colours, last song. Only session / user / membership / deviceId are migrated today. Flutter's token lives in an AES-encrypted Hive box (`lib/services/storage_service.dart`, box `secure_storage_box`; key in Keychain as `hive_encryption_key`).
- [ ] **Flutter side of D17 is uncommitted in `../ghallelujah` and must ship in the next Flutter release:** `lib/services/session_handoff_service.dart` (called from `main.dart` after `StorageService.init()`), publish hooks in `lib/utils/session.dart`, and `lib/views/launch/flash.dart` signing out when native ended the session. The next Flutter release needs a version above native 4.0.3 (332) — Flutter `dev` is already 4.0.3+333.
- [ ] **CarPlay files added outside a dispatched task** (2026-09-30 note) — later work built on top of them, so they are effectively kept. Confirm and close.
- [ ] **Standing no-build constraint** — a background track once ran a real device `xcodebuild` despite the "no `xcodebuild`" rule (left a `build/` directory; now gitignored). If you launch more background build/verify tracks, tighten how that constraint is phrased/enforced and watch whether it recurs.
