# Reel ads — plan and what was built

Status: **built and pushed to `somesh` in all four repos; not deployed anywhere; not run on a physical device** · updated 2026-10-28 · sections 0-7 are identical in all four repos so they cannot drift; section 8 is what was built in the repo you are reading.

| Project | GitHub repo (`techpwstudio-ops`) | Local folder | Branch | Reel ads commits | Deploy |
|---|---|---|---|---|---|
| Backend | `gs_nh_backend` | `gs_nh_backend` | `somesh` | `915aba9` (also on `dev`), `afe4a0c` | 1st |
| Admin panel | `gh_admin` | `gh_admin` | `somesh` | `ef9f858` (also on `dev-official`), `e7c0225` (shared with unrelated AI-management work) | 2nd |
| Flutter app | `ghallelujah_app` | `ghallelujah` | `somesh` | `140ef284`, `f44978e5` (reel foreground check) | 3rd |
| Native iOS | `hallelujah_native_ios` | `g-hallelujah-ios` | `somesh` | `e6913df` | 4th |

Section 2 describes the code **as it was before this work**, read from the code; each **Now:** note says what changed. Sections 3-5 describe what shipped. Nothing has been reproduced on a device or against real dev/QA/prod data; where a claim is a hypothesis it says so.

---

## 0. Status — 2026-10-28

| Part | State |
|---|---|
| Backend | **Built, pushed, not deployed.** Placement split and migration `20261027120000_ads_reel_between_tracks`, legacy alias, `asset_type_not_accepted`, per-format counters, `shown` / `servedNotShown`, `GET /admin/ads/caps`, `GET /admin/ads/viewer`, the per-listener trail, `POST /api/ads/track/not-shown` with its own rate-limit bucket. Not run against real data. The trail's extra Redis write on the serve path has **not been measured**. |
| Admin | **Built, pushed, not deployed.** *Caps in force* column, every accepted format shown (read-only chips), break-position select, Delivery with served / shown / served-never-shown, per-format split, not-shown reasons, the kept no-fill examples, a *Readiness* tab and a *Listener Lookup* page. No Pacing or Intro/Ad/Gap inputs. Not opened in a browser against a live API. |
| Flutter | **Built, pushed, not run on a device.** Per-format placements, reel screen redesign, video sized so nothing is cut, reel impression counted on the picture and only while the app is in the foreground (the foreground check is `f44978e5`, after `140ef284`), all 7 not-shown reasons, a 10 s start watchdog, no song counting on the device. |
| Native iOS | **Built, pushed, not run on a device.** Same as Flutter except: 6 of 7 not-shown reasons (no `expired_before_show`), and no break bank or preload (a break is asked for at the song change). The `squareImageUrl` guard and the 6-song pacing are gone. |

The apps must not ship before the backend (§5). The Flutter cropping cause is still a hypothesis (§2.3).

### 0.1 What differs from this plan

| Plan said | What shipped | Status |
|---|---|---|
| §4.6: a full-width white CTA pill with a `›` chevron; the Skip chip below the screen; the heart at the right edge, mid-video | The CTA is a white pill sized to its label, centred, no chevron; the Skip chip is in the top row, left of ⋮; the heart is bottom-right, directly above the CTA (both apps) | Accepted 2026-10-28 (§7.4) |
| §4.6: "the impression fires when the video is on screen, as it does now" | That was true of Flutter only; iOS counted at `play()`. Both apps now count a reel once the painted video has been on screen 0.5 s **with the app in the foreground**; leaving the foreground restarts the half second. iOS shipped with that; Flutter gained the foreground check in `f44978e5` | Accepted 2026-10-28 (§7.5) |
| D5: "the admin hides Pacing for the two break placements" | Wrong premise: the admin has **no Pacing input for any placement**. `pacingEveryN` is reachable only through `PATCH /admin/ads/placements/:key` | Corrected in §3 |
| §5 rollback: two admin-panel edits | Three steps, and the first and third are not panel edits | Corrected in §5 |
| §4.4: `servedNotShown = fill − shown`; the trail written per serve | `max(0, fill − shown)`, because a serve just before IST midnight can be confirmed just after it; the trail is also written on a confirmed impression (`shown`) and on a not-shown report | Corrected in §4.4 |
| §4.5: rate-limited "like the other track endpoints" | Its own bucket, `track:not-shown`; over the limit it answers 204, never 429. Deduped once per token | Corrected in §4.5 |
| Not in the plan | Skip pressed before the ad is ready: no impression and no not-shown report (both apps). `fill` is counted once the response payload exists, not at selection: a signing failure used to count a fill and an error (backend bug fix, D162) | Shipped |

---

## 1. What was asked

1. Reel (video) ads are served from the placement `audio_between_tracks`, the same one audio ads use. That name is misleading; ads should have names that say what they are.
2. The admin panel needs to show **ad capping**, and to say **why an ad was not shown**. In testing, frequency was set high and no ad appeared.
3. Reel video is **cropped in both apps**. Required: the video is as wide as the screen and its height follows from the video's own aspect ratio. The reel screen also drops the audio-player look (progress bar, title, transport) and follows the shared Spotify-style screenshot — similar, not identical, in our own design.

---

## 2. What the code did before this work

### 2.1 Naming

- `AdsPlacement` key `audio_between_tracks` accepted `["audio_ad", "reel_video"]` (`prisma/seed/ads.js`); the seed comment said it was one placement "rather than splitting into two". **Now:** it accepts `["audio_ad"]`, and reels are on `reel_between_tracks` (§4.1).
- A separate placement `feed_reel` ("Reel feed — video ad", disabled, "M2") exists for an in-feed reels list the apps do not have yet. So "reel" already names two different things; `feed_reel` is untouched.
- Creatives are not bound to a placement (D32), so a placement's accepted types are the whole definition of what it can show. Flutter asked the shared placement for a format by name (`assetType=audio_ad|reel_video`, taking turns); native did that only in preview mode. **Now:** both apps name the format on every break ask, each format on its own placement, taking turns, and try the other format when the first has nothing.
- No client compares `ad.placement` to a string, so the key could change without breaking parsing.

### 2.2 Why an ad may not show — candidates, none confirmed for the tester's case

Server (a 204 with a reason; the reasons are counted, see 2.4):

| # | Cause | Where |
|---|---|---|
| S1 | Platform floor is **1 impression / 30 min and 3 / day, per campaign, per listener**. A placement replaces a tier only if it sets one. The admin's "Cap / Person / Day" sets the *daily* tier only, so the 30-minute rule stays unless "Short Window" is also filled in. One test campaign therefore shows at most one ad per 30 min per device however high the daily cap is. **Now:** the admin's *Caps in force* column shows this, from `GET /admin/ads/caps`. | `frequency.service.js` `resolveFrequencyRules`, D135 |
| S2 | Caps count **confirmed impressions**, keyed on the listener: user id when signed in, else the `device-id` header, else IP. | `serving.controller.js` `resolveViewer` |
| S3 | A signed-in listener with an active premium subscription (owner or family member) is never served: `ad_free_viewer`. A tester account with a plan looks exactly like "ads broken". **Now:** the Listener Lookup says so. | `adFree.service.js` |
| S4 | Creative needs a primary asset and `active`; campaign must be live, approved, funded, in budget and inside its dates; targeting by country / platform / city (geo comes from IP, so local and private IPs match nothing). | `serving.service.js`, `adsDiagnostics.service.js` |
| S5 | Candidate set is cached 60 s per placement. | `serving.service.js` |

Client (the server never sees a request, so there is no 204 to count):

| # | Cause | Where |
|---|---|---|
| C1 | **Native dropped a served ad unless `squareImageUrl` was present.** A reel-only campaign was served, spend reserved, and the app silently discarded it. Flutter had already removed that guard. **Now:** removed in native too. | `AdPacingController.swift` `maybeStartAdBreak` |
| C2 | **Native asked only after `pacingEveryN ?? 6` songs**; Flutter had no device-side count for breaks. **Now:** neither app counts songs (D5). Every song change asks; the per-format 60 s no-fill backoff (C4) bounds the asking. | `AdPacingController.swift`; `bloc.dart` |
| C3 | `breakPosition` (`pre_roll`/`post_roll`) is read by Flutter, not by native. **Now:** editable in the admin (a select on the two break placements); native still does not read it. | `break_position.dart`; no native match |
| C4 | After any 204 both apps stay quiet for `Retry-After` (60 s) per placement+format. Unchanged. | `ad_serve_gate.dart`, `AdServeGate.swift` |
| C5 | A signed-in subscriber is blocked on the device before any request (`hasActiveSubscription`). Unchanged. | `ads_repository.dart` `_blockedReason` |
| C6 | Flutter's per-open preview ask only exists in builds with `AppConfig.adsPreviewMode`. **Now:** unchanged; native has a guarded `forcePreviewAdBreak` that nothing calls (left alone). | `audio_player_screen.dart` |

### 2.3 Cropping

- **Native: was definitely cropped.** `AdVideoSurface` set `videoGravity = .resizeAspectFill`, so a 9:16 video on a 19.5:9 phone lost about 18 % of its width. **Now:** the reel is drawn with `.resizeAspect` in a frame of the video's own shape (`reelVideoSize`), so nothing is cut.
- **Flutter: not cropped by the fit.** `_AdBreakVideo` already used `FittedBox(BoxFit.contain)`. What covered the video was the overlay: a 92 %-black scrim plus a five-row control panel over the bottom, and a 65 % scrim over the top. That is probably what the tester saw as cropping. **This is still a hypothesis** — it needs the tester's screenshot or screen recording. **Now:** the overlay is gone as part of the planned redesign; nothing else was changed on the strength of the hypothesis.
- Sizing rule (both apps, **now** `reelVideoSize`): `width = available width`, `height = width / videoAspectRatio`, centred on black. If that height exceeds the available height (iPad, landscape, very short screens) it scales down to fit, so nothing is cut. A spinner shows until the player reports the video's shape; no shape is guessed. The backend validates `reel_video` at 9:16 ± 0.02.

### 2.4 What the admin panel had and lacked

- `GET /admin/ads/delivery` returned **reason counts** and `samples[]` (recent no-fill examples); the panel showed the counts and dropped `samples`. **Now:** the samples are rendered.
- `GET /admin/ads/diagnostics` (the readiness audit) was not called anywhere in the panel. **Now:** it drives the *Readiness* tab on Delivery.
- `PATCH /admin/ads/placements/:key` accepts `pacingEveryN`, `breakPosition`, `introSeconds`, `displaySeconds`, `gapSeconds`, `minListenSeconds`, `minListenPercent`, `acceptedAssetTypes`. The placement table edited price, daily cap, short window and on/off. **Now:** it also edits `breakPosition` on the two break placements and shows accepted formats as read-only chips. There is still no input for Pacing, Intro/Ad/Gap, the listen gate or accepted formats; those are API-only.
- Missing everywhere before this work, all **now** added (§4.4): per-format counters; anything per listener; an effective-caps view; and served-but-never-shown.

---

## 3. Decisions — the defaults that shipped, all confirmed 2026-10-28

| # | Decision | Shipped | Alternative |
|---|---|---|---|
| D1 | Name of the reel placement | `reel_between_tracks`, label "Reel ad between tracks (9:16 video)" | `video_between_tracks` |
| D2 | Asset-type key `reel_video` | **Kept.** It names a *shape* (9:16), is stored on every creative and sent on the wire; renaming buys nothing and breaks old builds. | — |
| D3 | `audio_between_tracks` | Narrowed to `["audio_ad"]` | keep both accepted forever |
| D4 | Old builds that ask `audio_between_tracks` + `assetType=reel_video` | Server **aliases** exactly that pair to `reel_between_tracks`, whether or not that slot is enabled. On by default; off only when `ADS_LEGACY_REEL_ALIAS` is the string `false` (an env change needs an API restart). | no alias: old builds lose reels |
| D5 | Pacing for breaks | **No song counting on the device**, in both apps. The admin panel has no Pacing input for any placement, so there was nothing to hide; `pacingEveryN` can be set only through the PATCH API, the migration leaves it null on the break slots, and no app reads it for breaks. | honour `pacingEveryN` in both apps |
| D6 | Reel screen actions | Like (heart), the existing ⋮ menu, Skip (when the creative is skippable), CTA pill (when the ad has a destination), a small "Sponsored" tag. **No** comment or share: ads have neither. | add them later |
| D7 | Not-shown reports | Token-bound `POST /api/ads/track/not-shown`, closed reason list (§4.5) | device logs only |

D1, D5 and D6 were product calls, as were the layout and impression-timing changes in §0.1; all were confirmed as shipped on 2026-10-28 (§7). D6 keeps the "Sponsored" tag because D155 requires every ad to be tagged.

---

## 4. Shared contract, as shipped

### 4.1 Placement split

New placement row `reel_between_tracks`: surfaces `["app"]` (the web has no video renderer and already sends `assetType=audio_ad`), accepted types `["reel_video"]`. Migration `20261027120000_ads_reel_between_tracks` copies from `audio_between_tracks`: `enabled`, `defaultFrequencyCapPerUserPerDay`, `frequencyRules`, `breakPosition`, `minListen*`, and **the open rate card** (a placement with no card is `placement_unpriced` — it would silently serve nothing), respecting `AdsRateCard`'s per-placement no-overlap constraint. `pacingEveryN` is left null (D5). It then sets `audio_between_tracks.acceptedAssetTypes = ["audio_ad"]` and adds `reel_between_tracks` to `adsCompanyAds.placementKeys` wherever `audio_between_tracks` is present, so company reel promos keep filling. Idempotent; a malformed `adsCompanyAds` row is skipped with a notice instead of aborting the migration.

### 4.2 Legacy alias (D4)

`placementAlias.js` `resolvePlacementKey`, called while the serve request is read, rewrites exactly `placement=audio_between_tracks` **and** `assetType=reel_video` to `reel_between_tracks` before selection — for paid and company ads alike, and without checking whether `reel_between_tracks` is enabled. Counters, samples, the trail and the response `placement` field then carry the new key. Nothing else is aliased: an old build that asks `audio_between_tracks` with no `assetType` gets audio only. Off only when `ADS_LEGACY_REEL_ALIAS` is exactly `false`.

### 4.3 No-fill vocabulary

- New reason `asset_type_not_accepted`: the asked-for `assetType` is not one the placement accepts (before, this was folded into `no_candidates`, which reads as "nothing booked").
- Samples, the trail and the per-format counters carry `assetType`, so audio and reel misses are separate.

### 4.4 Admin endpoints (all `ads.view`, read-only)

| Endpoint | Answers |
|---|---|
| `GET /admin/ads/caps?placement=&campaignId=` | The **effective** caps: each rule with its source (platform / placement / campaign), the platform rules a placement displaced, and the collapsed result. Built from the same resolver serving uses, so it cannot drift. |
| `GET /admin/ads/viewer?userId=\|email=\|deviceId=&placement=` | Exactly one of the three identifiers. How the listener is identified (`u:` / `d:`), ad-free status and why, with `placement` every candidate campaign's count per window against the cap and when the next impression is allowed, mutes, and the last 25 trail entries. |
| `GET /admin/ads/delivery` (extended) | Adds `shown` (confirmed impressions), `servedNotShown = max(0, fill − shown)`, per-format counts, not-shown reasons, and passes `samples` through. Existing fields unchanged. |
| `GET /admin/ads/diagnostics` | Existed; the panel's *Readiness* tab now uses it. |

**Trail.** A per-listener Redis list `ads:trace:<viewerHash>`, newest 25, 24 h TTL refreshed on write, keyed on the same `hashViewer()` the frequency keys use (no raw id stored). Written on every serve outcome (fill, no-fill, company fill, error), on a confirmed impression (`shown`) and on a not-shown report: one pipelined `LPUSH`/`LTRIM`/`EXPIRE`, never awaited, cannot throw. Entry: time, kind, placement, assetType, outcome, reason, and a bounded meta (the blocking cap window, candidate count). `ADS_VIEWER_TRACE=false` turns it off, read per call. **Its cost on the serve path is unmeasured; measure on QA before production.**

### 4.5 `POST /api/ads/track/not-shown` (D7)

Body `{ token, reason }`, behind `adsAppCheck` then its own rate limit. The token is the signed impression token of an ad the server *did* serve, so a report can only concern a real serve to the caller. Paid tokens only: a company ad's token gets the same 204 and is recorded nowhere, so the apps do not send it. `reason` is a closed list: `unplayable_format`, `asset_missing`, `preload_failed`, `video_init_failed`, `muted_campaign`, `superseded`, `expired_before_show`; anything else is dropped. Once per token (`SET ads:notshown:<nonce> NX`, TTL = the impression token's, default 600 s). Rate limit: bucket `track:not-shown` (`ads:rl:track:not-shown:<ip>`, same limit and window as the other track calls); over it the report is dropped with a 204, never a 429. Always 204. Counted per placement and format and written to the trail. Never touches billing.

The apps keep one verdict per token: a token confirmed as shown is never reported as not shown, and the other way round (the server has no check between the two). Flutter sends all seven reasons; iOS sends six — it has no break bank, so it never holds an ad long enough for `expired_before_show`. What this cannot see: a request the app never made (C4, C5). That shows up as low `requests` on the placement, not as a reason.

### 4.6 Reel screen layout (both apps, as shipped)

Black background, nothing else behind the video.

```
┌────────────────────────────┐
│ Sponsored     Skip (n)  ⋮  │  ← safe-area top: tag left; Skip chip (only if skippable) and ⋮ right
│ ┌────────────────────────┐ │
│ │   video, full width    │ │  ← width = screen width, height = width / aspect,
│ │   centred vertically   │ │     scaled down to fit if that is too tall
│ └────────────────────────┘ │
│                         ♡  │  ← like (AdReaction.like), bottom-right, above the CTA
│       [ Learn More ]       │  ← white pill sized to its label, centred, no chevron;
└────────────────────────────┘     shown only when the ad has a destination
```

- No scrubber, no time labels, no transport, no advertiser/headline rows, no "Your music will continue" line. Tap on the video pauses / resumes; a play glyph shows while paused. A spinner shows until the first frame's shape is known.
- CTA label is the creative's `ctaLabel`, falling back to the localised "More info"; it opens through the existing ad-action path. ⋮ "Close ad" respects the creative's skip lock. Impression: in both apps a reel counts once its painted video has been on screen 0.5 s with the app in the foreground; leaving the foreground restarts the half second. Audio ads keep the audio layout and their impression timing.

---

## 5. Order of work and rollout

Deploy **backend → admin → Flutter → iOS**. The backend goes first and is additive: old apps keep working through the alias. The admin needs its endpoints. Both apps ask `reel_between_tracks`, so **they must not ship before the backend**: against an older backend that placement is unknown and every reel ask is a `placement_unknown_or_disabled` no-fill. Neither app falls back to the legacy key.

| App build | Backend | Result |
|---|---|---|
| old | new | Works. Reel asks aliased to the new placement. Audio unchanged. |
| new | new | Intended. |
| new | old | Reels never serve. Don't ship in this order. |

**Rollback — three steps; the first two alone leave every old build asking a disabled slot:**

1. Re-add `reel_video` to the audio slot with an API call (the panel shows accepted formats read-only): `PATCH /admin/ads/placements/audio_between_tracks` with `{"acceptedAssetTypes":["audio_ad","reel_video"]}`.
2. Set `reel_between_tracks.enabled=false` — the panel's on/off toggle, or the same PATCH with `{"enabled":false}`.
3. Set `ADS_LEGACY_REEL_ALIAS=false` in the API's environment and **restart the API**.

New builds ask `reel_between_tracks` by name and stay without reels until the split is redone. There is no down migration; these steps restore the old behaviour without one.

---

## 6. Verification — what was run and what was not (this rewrite itself re-ran no test suite)

| Part | Run | Not run |
|---|---|---|
| Backend | At `915aba9`: 991 ads tests (Jest) passed; 62 checks against a real local Postgres 16 + Redis through the real routers; the migration applied twice to a seeded database and through `prisma migrate deploy` to an empty one; lint clean on every changed file. `afe4a0c` (rate-limit bucket, dedupe, docs) added tests; no pass count is recorded for it. Full-repo `npm run lint`: 178 pre-existing errors in 80 files, none in touched files. `swagger:check`: ~499 pre-existing warnings. | The full API process (needs Firebase credentials); anything on dev, QA or prod; the trail's write cost. |
| Admin | At `ef9f858`: `tsc` clean, 282 vitest tests passed (33 new), lint errors unchanged (pre-existing). `e7c0225` (Readiness, Listener Lookup) added tests; no pass count is recorded for it. | A browser against a live API. |
| Flutter | `flutter analyze`: 2 issues, both pre-existing. `flutter test`: the only failures are 3 pre-existing files (`test/auth_unified_otp_test.dart`, `test/views/plans_widgets_test.dart`, `test/widget_test.dart`). `f44978e5` (foreground check), on Flutter 3.47.8: `flutter analyze` on its 3 files — 1 issue, the pre-existing unused `logo` in `ad_break_screen.dart`; all 330 tests in `test/ads/` passed, and the 3 new foreground tests fail with the check removed. | A device; any backend with this work deployed. |
| Native iOS | The test target compiles at the tip (it did not at the commit before this work); 438 tests in 77 suites passed. | A device; any backend with this work deployed. |

---

## 7. Questions — 1-5 decided 2026-10-28, 6-7 still open

1. **Decided:** D1 — keep `reel_between_tracks` as the name.
2. **Decided:** D5 — no song counting on the device, in both apps; `pacingEveryN` stays unread for breaks.
3. **Decided:** D6 — keep like, ⋮, Skip, CTA and "Sponsored", with no comment or share.
4. **Decided:** layout as shipped (§0.1) — the content-sized centred CTA without a chevron, Skip in the top row beside ⋮, the heart bottom-right above the CTA.
5. **Decided:** a reel counts after its painted video has been on screen 0.5 s with the app in the foreground, in both apps. On iOS it replaces counting at `play()`, so iOS counts fewer reel impressions than before for the same plays.
6. Can you send the tester's screenshot of the cropped reel on Flutter? Without it the Flutter half of the cropping stays a hypothesis.
7. Which user / device did the failed test use? The Listener Lookup will answer "why", but only once the backend is deployed and the test is repeated.

---

## 8. Native iOS app — `hallelujah_native_ios` (folder `g-hallelujah-ios`), branch `somesh`, as built

Commit: `e6913df`. `c69fc4b` is not part of reel ads. Ship last, after the backend (§5): against an older backend every reel ask is a no-fill.

| # | Planned | As built | Files |
|---|---|---|---|
| N1 | Placement per format, both formats in turn (port Flutter's `serveBreak`) | As planned, in a pure `AdBreakFill`: each format on its own placement, taking turns, the other format tried when the first has nothing. | `App/Platform/Ads/AdBreakFill.swift`, `App/Data/Repositories/AdsRepository.swift` |
| N2 | Drop the `squareImageUrl` guard | Done: a break needs a playable soundtrack or video, not a picture. | `App/Platform/Ads/AdPacingController.swift` |
| N3 | Stop counting songs; keep the in-flight guard | Done: every song change asks (D5). It does not ask while one song is on repeat, except in preview (`isLoopingOneSong`). `pacingEveryN` is still read for the player card and rail ads (`PlayerAdController`, `RailAdStore`), not for breaks. | `AdPacingController.swift`, `App/Platform/Audio/AudioEngine.swift`, `App/Platform/Audio/QueueController.swift` |
| N4 | Reel screen (§4.6): `.resizeAspect` in a `reelVideoSize` frame, scrim and control panel removed | Built, with the layout changes in §0.1. A plain `AVPlayerLayer` view with an explicit frame. The impression counts once the painted video has been on screen 0.5 s **while `scenePhase == .active`**; it used to count at `play()`. The rules live in a pure `AdBreakState`. | `App/Features/Player/Views/AdBreakView.swift`, `App/Platform/Ads/ReelVideoSize.swift`, `App/Platform/Ads/AdBreakState.swift`, `App/Features/Player/Ads/AdBreakMiniBanner.swift` |
| N5 | Not-shown reports through `AdsRepository` | 6 of the 7 reasons. `expired_before_show` exists in the enum but nothing emits it: iOS has no break bank, so it never holds a served ad long enough. Same one-verdict-per-token rule as Flutter. | `AdsRepository.swift`, `AdPacingController.swift` |
| N6 | `breakPosition` not read (out of scope) | Unchanged: still not read. A break happens at the song change. | — |
| N7 | Reuse existing strings; check `Localizable.xcstrings` first | Added Play / Pause (the paused-reel control). The same file also carries the re-keyed plurals that `HomeMetrics` uses from `c69fc4b`. | `App/Resources/Localizable.xcstrings` |
| N8 | Tests | `AdBreakFillTests`, `AdBreakStateTests`, `AdNotShownTests`, `AdPacingControllerTests`, `ReelVideoSizeTests`, `AdsWireSupport`, `AppConfigurationTests`. Results in §6. | `Tests/Platform/Ads/`, `Tests/Core/Configuration/` |

**Pre-existing differences from Flutter, left alone**

- The `adsEnabled` gate.
- `forcePreviewAdBreak` exists but nothing calls it.
- Lock-screen / remote commands, the sleep timer and logout do not end an ad break.
- No break bank or preload: a break is asked for at the song change.
- Stale `.dev` / `.staging` comments in `Development.xcconfig`, `Staging.xcconfig` and `progress.md` Q7. The bundle id is `com.hallelujah.user` in every environment.

**Risks still open**

- Counting at "0.5 s on screen while active" instead of at `play()` lowers iOS reel impressions for the same plays. Accepted 2026-10-28 (§7.5); Flutter now applies the same foreground rule (`f44978e5`).
- Breaks now come at every song change (no 6-song default), so listeners see more breaks than before; the server's caps decide how many. This is intended, but it is a visible change.
- Sizing and the hidden player chrome in `FullPlayerView` are built from code reading only; nothing has run on a device.
