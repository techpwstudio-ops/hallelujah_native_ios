# CarPlay QA matrix (T53)

Code: `App/Platform/CarPlay/`. Content is fetched through the same repositories
as the phone UI; playback goes through the shared `QueueController` /
`AudioEngine`, so there is one player, never two.

Status key: ☐ not yet run · ✅ passed · ❌ failed. **Nothing below has been run
yet** — the code has only been compiled by CI (if at all), never exercised in
the CarPlay simulator or on a head unit.

## Connect / launch

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 1 | Connect with app closed (car-only launch) | Tab bar appears; every tab shows "Loading…" then fills; no phone UI needed | ☐ |
| 2 | Connect with app running, nothing playing | Same; Home rails appear in layout order as artwork lands | ☐ |
| 3 | Connect while a song is playing on the phone | Tabs fill; row dot on the playing song; Now Playing shows the same song and position; no second audio stream | ☐ |
| 4 | Connect while signed out | All four tabs show "Sign in on your iPhone…" | ☐ |
| 5 | Disconnect / reconnect repeatedly | No crash, no leaked observers; second connect rebuilds cleanly; artwork renders from disk cache with no network | ☐ |

## Tabs

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 6 | Home | Rails render; Trending is a 2-column grid (iOS 26+); tap tile plays/drills; tap row title opens See All | ☐ |
| 7 | Recents | "Continue Your Journey" items; song cards play (resolved by title search), playlist/artist/album cards drill in | ☐ |
| 8 | Search | Hint row + Browse Genres; tap a genre lists its songs | ☐ |
| 9 | Library | Liked Songs, Downloads, Playlists rows | ☐ |

## Pushed templates

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 10 | Liked Songs | Lists up to 100; tap plays with the list as the queue (source `favourite`) | ☐ |
| 11 | Downloads | Only completed + file-on-disk songs; plays offline with no network | ☐ |
| 12 | Playlists | Company playlists first, then user playlists; each opens its songs | ☐ |
| 13 | Creator / playlist / album / genre songs | Each lists songs and plays; queue source matches (`creator`, `companyPlaylist`, `album`, `genre`, `userPlaylist`) | ☐ |
| 14 | Home "See All" | Every row in the rail, not just the first few | ☐ |

## Guards and limits

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 15 | Rapid double/triple tap on a drill-down row | One template pushed (`isPushing` guard) | ☐ |
| 16 | Drill 5 levels deep, then tap another drill-down | Ignored, no crash (`maxTemplateDepth` = 5) | ☐ |
| 17 | Very large library | Lists capped at 100 rows (`maxFetchedRows`) | ☐ |
| 18 | Offline, then connect | Home falls back to cached layout; Downloads still works; other tabs show their empty row | ☐ |

## Now Playing

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 19 | Heart button | Toggles instantly with a brief enlarged "pop"; reverts if the request fails | ☐ |
| 20 | Favourite toggled on the phone while CarPlay shows Now Playing | Heart updates; an open Liked Songs list refreshes | ☐ |
| 21 | Play/pause/next/previous/seek from the car | Phone UI follows (same `MPRemoteCommandCenter` owner, `NowPlayingCoordinator`) | ☐ |
| 22 | Start on phone → continue in car → control from car | No duplicate players | ☐ |

## Known gaps

- Siri "play X in Hallelujah": implemented via `SiriIntentsExtension` + `SiriPlayService`; needs a device test (CarPlay-only cold launch unverified).
- Recent *song* cards are resolved by searching their title (no song-by-id endpoint).
- Downloads and Playlists lists do not live-refresh while open (Liked Songs does).
- Auth guard is a simple signed-in check at connect time.
