# Reel ads — plan

Status: **plan, nothing built yet** · 2026-10-27 · sections 1-7 are identical in all four repos so they cannot drift; section 8 is specific to the repo you are reading.

| Project | Repo | Branch | Order |
|---|---|---|---|
| Backend | `gs_nh_backend` | `dev` | 1st |
| Admin panel | `gh_admin` | `dev-official` | 2nd |
| Flutter app | `ghallelujah_app` | `dev` | 3rd |
| Native iOS | `hallelujah_native_ios` | `main` | 4th |

Nothing below has been run. This environment has no database, Redis, Flutter or Swift toolchain and no device, so everything in section 2 is **read from the code**, not reproduced. Where a claim is a hypothesis it says so.

---

## 1. What was asked

1. Reel (video) ads are served from the placement `audio_between_tracks`, the same one audio ads use. That name is misleading; ads should have names that say what they are.
2. The admin panel needs to show **ad capping**, and to say **why an ad was not shown**. In testing, frequency was set high and no ad appeared.
3. Reel video is **cropped in both apps**. Required: the video is as wide as the screen and its height follows from the video's own aspect ratio. The reel screen also drops the audio-player look (progress bar, title, transport) and follows the shared Spotify-style screenshot — similar, not identical, in our own design.

---

## 2. What the code does today

### 2.1 Naming

- `AdsPlacement` key `audio_between_tracks` accepts `["audio_ad", "reel_video"]` (`prisma/seed/ads.js`). The seed comment says it was one placement "rather than splitting into two".
- A separate placement `feed_reel` ("Reel feed — video ad", disabled, "M2") exists for an in-feed reels list the apps do not have yet. So "reel" already names two different things; this plan keeps `feed_reel` untouched.
- Creatives are not bound to a placement (D32), so a placement's accepted types are the whole definition of what it can show. Flutter asks the shared placement for a format by name (`assetType=audio_ad|reel_video`, taking turns). Native does that only in preview mode; in normal use it sends no `assetType` and takes whatever the server picks.
- No client compares `ad.placement` to a string, so the key can change without breaking parsing.

### 2.2 Why an ad may not show — candidates, none confirmed for the tester's case

Server (a 204 with a reason; the reasons are counted, see 2.4):

| # | Cause | Where |
|---|---|---|
| S1 | Platform floor is **1 impression / 30 min and 3 / day, per campaign, per listener**. A placement replaces a tier only if it sets one. The admin's "Cap / Person / Day" sets the *daily* tier only, so the 30-minute rule stays unless "Short Window" is also filled in. One test campaign therefore shows at most one ad per 30 min per device however high the daily cap is. | `frequency.service.js` `resolveFrequencyRules`, D135 |
| S2 | Caps count **confirmed impressions**, keyed on the listener: user id when signed in, else the `device-id` header, else IP. | `serving.controller.js` `resolveViewer` |
| S3 | A signed-in listener with an active premium subscription (owner or family member) is never served: `ad_free_viewer`. A tester account with a plan looks exactly like "ads broken". | `adFree.service.js` |
| S4 | Creative needs a primary asset and `active`; campaign must be live, approved, funded, in budget and inside its dates; targeting by country / platform / city (geo comes from IP, so local and private IPs match nothing). | `serving.service.js`, `adsDiagnostics.service.js` |
| S5 | Candidate set is cached 60 s per placement. | `serving.service.js` |

Client (the server never sees a request, so there is no 204 to count):

| # | Cause | Where |
|---|---|---|
| C1 | **Native drops a served ad unless `squareImageUrl` is present.** A reel-only campaign (no square image creative in the same campaign) is served, spend is reserved, and the app silently discards it. Flutter `dev` already removed that guard. | `AdPacingController.swift` `maybeStartAdBreak` |
| C2 | **Native asks only after `pacingEveryN ?? 6` songs.** The seed sets 6 on `audio_between_tracks`. Flutter `dev` has no device-side count for breaks (asks every song, server decides). So the two apps behave differently on the same dashboard setting, and the admin has no Pacing field to see or change it. | `AdPacingController.swift`; `audio_break_planner.dart` |
| C3 | `breakPosition` (`pre_roll`/`post_roll`) is read by Flutter, not by native at all. Not editable in the admin panel either. | `break_position.dart`; no native match |
| C4 | After any 204 both apps stay quiet for `Retry-After` (60 s) per placement+format. | `ad_serve_gate.dart`, `AdServeGate.swift` |
| C5 | A signed-in subscriber is blocked on the device before any request (`hasActiveSubscription`). | `ads_repository.dart` `_blockedReason` |
| C6 | Flutter's per-open preview ask only exists in builds with `AppConfig.adsPreviewMode`. A tester on a build without it waits for a real song boundary. | `audio_player_screen.dart` |

### 2.3 Cropping

- **Native: definitely cropped.** `AdVideoSurface` sets `videoGravity = .resizeAspectFill`. A 9:16 video on a 19.5:9 phone is scaled to the full screen height, so about 18 % of its width (9 % each side) is cut off. The comment even says "cover-fit".
- **Flutter: not cropped by the fit.** `_AdBreakVideo` already uses `FittedBox(BoxFit.contain)`. What covers the video is the overlay: a 92 %-black scrim plus a five-row control panel (advertiser row, scrubber, transport, footer, CTA) stacked over the bottom of it, and a 65 % scrim over the top. That is probably what the tester sees as cropping. **This is a hypothesis** — it needs the tester's screenshot or screen recording to confirm. The redesign removes the overlay either way.
- Sizing rule (both apps): `width = screen width`, `height = width / videoAspectRatio`, centred vertically on black. If that height exceeds the available height (iPad, landscape, very short screens) fall back to *fit* so nothing is cut. The backend validates `reel_video` at 9:16 ± 0.02, so on any phone taller than 16:9 the width rule applies exactly.

### 2.4 What the admin panel has and lacks

Backend already has, admin panel does not use or only partly uses:

- `GET /admin/ads/delivery` — per placement per day: requests, fills, no-fills, **reason counts**, and `samples[]` (recent no-fill examples with candidate counts and the cap window that blocked). The panel (`AdsDelivery.tsx`) shows the reason counts and **ignores `samples`**.
- `GET /admin/ads/diagnostics` — readiness audit ("why has this placement never served": enabled → priced → creatives → live → eligible). **Not called anywhere in the panel.**
- `PATCH /admin/ads/placements/:key` accepts `pacingEveryN`, `breakPosition`, `introSeconds`, `displaySeconds`, `gapSeconds`, `minListenSeconds`, `minListenPercent`, `acceptedAssetTypes`. The panel's placement table edits only price, daily cap, short window, on/off (`PlacementPatch` lists `pacingEveryN` but no input renders it).

Missing everywhere:

- **Counters are per placement, not per format.** On the shared placement an audio miss and a reel miss are one number.
- **Nothing per listener.** "Why did *my* phone get nothing" cannot be answered; frequency state is Redis-only and only visible by reading keys.
- **No effective-caps view.** The three sources (platform, placement, campaign) combine by tier and the panel shows none of the result.
- **Served-but-never-shown** (the app received an ad and dropped it) is invisible.

---

## 3. Decisions — defaults chosen so work can proceed; veto before the backend ships

| # | Decision | Default | Alternative |
|---|---|---|---|
| D1 | Name of the reel placement | `reel_between_tracks`, label "Reel ad between tracks (9:16 video)" | `video_between_tracks` |
| D2 | Asset-type key `reel_video` | **Keep.** It names a *shape* (9:16), is stored on every creative and sent on the wire; renaming buys nothing and breaks old builds. | — |
| D3 | `audio_between_tracks` | Narrowed to `["audio_ad"]` | keep both accepted forever |
| D4 | Old builds that ask `audio_between_tracks` + `assetType=reel_video` | Server **aliases** them to `reel_between_tracks` (env `ADS_LEGACY_REEL_ALIAS`, default on), so video ads keep working until old builds retire | no alias: old builds lose reels |
| D5 | Pacing for breaks | **Do not count songs on the device** (matches Flutter `dev`). Native is brought in line. The admin hides Pacing for the two break placements instead of showing a field no app honours. | honour `pacingEveryN` in both apps |
| D6 | Reel screen actions | Like (heart), the existing ⋮ menu, Skip (when the creative is skippable), CTA pill, a small "Sponsored" tag. **No** comment or share: ads have neither. | add them later |
| D7 | Not-shown reports | Token-bound `POST /api/ads/track/not-shown`, closed reason list | skip it; use device logs only |

Two of these are product calls I would rather you make than me: D5 (it changes what the dashboard's Pacing means for native) and D6 (the screenshot has comment and share icons; there is nothing for them to do on an ad). D6 also keeps the "Sponsored" tag because D155 requires every ad to be tagged.

---

## 4. Shared contract

### 4.1 Placement split

New placement row `reel_between_tracks`: surfaces `["app"]` (the web has no video renderer and already sends `assetType=audio_ad`), accepted types `["reel_video"]`. A migration copies from `audio_between_tracks`: `enabled`, `defaultFrequencyCapPerUserPerDay`, `frequencyRules`, `breakPosition`, `minListen*`, and **the open rate card** (a placement with no card is `placement_unpriced` — it would silently serve nothing). `pacingEveryN` is left null (D5). It also needs `AdsRateCard`'s own columns (`billingEventKey`, `pricingModel`, a fresh `effectiveFrom`) and must respect that table's per-placement no-overlap constraint. The migration then sets `audio_between_tracks.acceptedAssetTypes = ["audio_ad"]` and adds `reel_between_tracks` to `adsCompanyAds.placementKeys` wherever `audio_between_tracks` is present, so company reel promos keep filling. Idempotent: re-running changes nothing.

### 4.2 Legacy alias (D4)

In the serve controller, `placement=audio_between_tracks` **and** `assetType=reel_video` is rewritten to `reel_between_tracks` before selection. Counters, samples and the response `placement` field then carry the new key. Nothing else is aliased: an old build that asks `audio_between_tracks` with no `assetType` gets audio only.

### 4.3 No-fill vocabulary

- New reason `asset_type_not_accepted`: the asked-for `assetType` is not one the placement accepts (today this is folded into `no_candidates`, which reads as "nothing booked").
- Samples, the viewer trace and a new per-format counter carry `assetType`, so audio and reel misses are separate even on one placement.

### 4.4 Admin endpoints (all `ads.view`, read-only)

| Endpoint | Answers |
|---|---|
| `GET /admin/ads/caps?placement=&campaignId=` | The **effective** caps: each rule with its source (platform / placement / campaign), the tier it replaces, and the collapsed result. Built from `resolveFrequencyRules` + `collapseRules`, so it cannot drift from serving. |
| `GET /admin/ads/viewer?userId=\|email=\|deviceId=&placement=` | For one listener: how they are identified (`u:` / `d:`), ad-free status and why, **per candidate campaign** the count in each window against the cap and when the next impression is allowed, mutes, and the last 25 serve decisions. |
| `GET /admin/ads/delivery` (extended) | Adds `shown` (confirmed impressions), `servedNotShown`, `byAssetType`, and reason counts per format. Existing fields unchanged. |
| `GET /admin/ads/diagnostics` | Exists. The panel starts using it. |

**Viewer trace.** The serve path writes one entry per request to a per-listener Redis list (`ads:trace:<viewerHash>`, newest 25, 24 h TTL, fire-and-forget in one pipeline, never awaited on the response path, errors swallowed). Entry: time, placement, assetType, outcome, reason, the cap window that blocked, candidate count. The key uses the same `hashViewer()` the frequency keys use; no raw id is stored. `ADS_VIEWER_TRACE=false` turns it off.

### 4.5 `POST /api/ads/track/not-shown` (D7)

Body `{ token, reason }`. The token is the signed impression token of an ad the server *did* serve, so a report can only be about a real serve, from the listener it was served to, and cannot be forged for someone else. `reason` is a closed list: `unplayable_format`, `asset_missing`, `preload_failed`, `video_init_failed`, `muted_campaign`, `superseded`, `expired_before_show`; anything else is dropped. Always answers 204. Counted per placement and format, written to the viewer trace. Rate-limited like the other track endpoints. Impression billing is untouched: a report never creates or cancels an event.

What this cannot see: a request the app never made (C2, C4, C5). Those show up as low `requests` on the placement, not as a reason.

### 4.6 Reel screen layout (both apps)

Black background, nothing else behind the video.

```
┌────────────────────────────┐
│ Sponsored              ⋮   │  ← safe-area top, small tag left, ⋮ right
│                            │
│ ┌────────────────────────┐ │
│ │                        │ │
│ │   video, full width    │ │  ← width = screen width, height = width / aspect
│ │   centred vertically   │ │
│ │                        │ │     ♡   ← like (existing AdReaction.like),
│ │                        │ │          right edge, over the video
│ └────────────────────────┘ │
│                            │
│  [  Learn More   ›  ]      │  ← white pill, full width, above bottom inset
└────────────────────────────┘
            Skip › (n)           ← only if the creative is skippable, existing chip
```

- No scrubber, no time labels, no transport, no advertiser/headline rows, no "Your music will continue" line.
- Tap on the video pauses / resumes (replaces the visible play-pause).
- CTA label is the creative's `ctaLabel`, falling back to the existing localised "More info" string; it opens through the existing `openAdAction`.
- The impression fires when the video is actually on screen, as it does now.
- Audio ads keep the current audio layout unchanged.

---

## 5. Order of work and rollout

1. **Backend** → migration + alias + reasons + endpoints + trace + not-shown. Deploy first; it is additive. Old apps keep working (alias).
2. **Admin** → needs the backend endpoints.
3. **Flutter**, then 4. **Native** → both ask `reel_between_tracks`, so **they must not ship before the backend**: against an older backend that placement is unknown and every reel ask would be a `placement_unknown_or_disabled` no-fill. They send the legacy key only if you ask for that fallback; I would not add it.

| App build | Backend | Result |
|---|---|---|
| old | new | Works. Reel asks aliased to the new placement. Audio unchanged. |
| new | new | Intended. |
| new | old | Reels never serve. Don't ship in this order. |

Rollback: re-add `reel_video` to `audio_between_tracks.acceptedAssetTypes` and set `reel_between_tracks.enabled=false`. Both are admin-panel edits.

---

## 6. Verification

| Part | Can I run it here | How it will be checked |
|---|---|---|
| Backend | Lint and Jest unit tests yes. Anything needing Postgres/Redis no. | New unit tests with mocked Prisma/Redis, as the existing ads tests do; `npm run lint`. Migration is read by eye and written to be idempotent; **it has not been applied to any database**. |
| Admin | `tsc`, lint, vitest yes. | Type-check, unit tests for the new pure helpers. No browser run against a live API. |
| Flutter | **No** — no SDK. | Code written to the existing patterns; tests updated; **you run `flutter analyze` and `flutter test`**. |
| Native iOS | **No** — no Swift. | Same; **you build in Xcode**. |

On a real device, the thing to check first for the cropping is a screenshot of the reel on the current build next to the new one.

---

## 7. Open questions for you

1. D1: is `reel_between_tracks` the name you want?
2. D5: should native stop counting songs (matches Flutter `dev`), or should both apps honour `pacingEveryN`?
3. D6: like only, or do you want the other icons from the screenshot anyway?
4. Can you send the tester's screenshot of the cropped reel on Flutter? Without it the Flutter half of the cropping stays a hypothesis.
5. Which user / device did the failed test use? The viewer lookup in 4.4 will answer "why", but only once it is deployed and the test is repeated.

---

## 8. Native iOS work — `hallelujah_native_ios`, branch `main`

Last, after Flutter, so it can follow the Flutter behaviour the previous steps settled. No Swift toolchain here: **nothing is compiled**; you build and run in Xcode (Swift 6, strict concurrency, `any` required for existentials — written to that).

| # | Step | Files |
|---|---|---|
| N1 | **Placement per format**, and **ask for both formats in turn**. Today production asks with no `assetType`, so after the split native would only ever be offered audio. Port Flutter's `serveBreak` / `isPlayableAdBreak` (`audio_ad`, `reel_video` with a playable URL). | `App/Platform/Ads/AdPacingController.swift`, new small helper beside it |
| N2 | **Drop the `squareImageUrl` guard** (C1): a break needs a playable soundtrack or video, not a picture — exactly Flutter `dev`'s rule. This is a likely cause of "served, never shown" today. | `AdPacingController.swift` |
| N3 | **Stop counting songs on the device** (D5, C2): ask at each song change like Flutter `dev`; the server's caps decide. Remove `tracksSinceLastAdBreak` and the default-6. Keep the in-flight guard. | `AdPacingController.swift` |
| N4 | **Reel screen** (4.6): new `ReelAdBreak` replaces `VideoAdBreak`. `AdVideoSurface` changes from `.resizeAspectFill` to `.resizeAspect` inside a frame computed by a pure `reelVideoSize(available:aspectRatio:)`; the scrim and `AdBreakControlPanel` are no longer drawn over the video. ⋮ via the existing `AdOptionsButton`, like via the existing thumb, Skip via the existing chip (`TimelineView`), CTA pill via `pacing.openAction`, "Sponsored" tag, tap to pause via `togglePause()`. Audio layout untouched. The video's natural aspect ratio comes from the `AVPlayerItem` presentation size. | `App/Features/Player/Views/AdBreakView.swift` |
| N5 | **Not-shown reports** (4.5) through `AdsRepository`, called when `playAdCreative` cannot build a URL or the item fails (`AVPlayerItem.status == .failed`). Endpoint with the other ads endpoints. | `App/Data/Repositories/AdsRepository.swift`, `AdPacingController.swift` |
| N6 | `breakPosition` is not read by native at all (C3). Out of scope here: native already breaks at a song change, which is the pre-roll behaviour. Said so rather than half-implemented; add it if you want parity. | — |
| N7 | Strings: reuse the existing localised "Skip" and "More Info" entries and the existing `AdSponsoredBadge` view; I will check `Localizable.xcstrings` before adding anything. | — |
| N8 | Tests (Swift Testing, `#expect`): `reelVideoSize` cases, placement-per-format, rotation order, "playable break" rule. | `Tests/` |

**Risks**

- This file's own header says the guard and the 6-song default were ported *as they were in Dart at the time*. Flutter has since moved; N2/N3 are catching native up, and they change observable cadence — more breaks than before. That is the intent, and it is the part to watch in testing.
- `AVPlayerViewController` sizing inside SwiftUI is easy to get subtly wrong without running it. I will use a plain `AVPlayerLayer`-backed view with an explicit frame so the sizing rule is the only thing that decides the geometry.
- `FullPlayerView` renders `AdBreakView` inline; the new reel screen must still hide the player chrome the way the current one does.
