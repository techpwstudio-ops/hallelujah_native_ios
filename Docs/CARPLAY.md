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
| 9 | Library | Liked Songs, Downloads, then the library's playlists (owned, followed, saved) listed directly, with no Playlists row | ☐ |

## Pushed templates

| # | Scenario | Expected | Status |
|---|----------|----------|--------|
| 10 | Liked Songs | Lists up to 100; tap plays with the list as the queue (source `favourite`) | ☐ |
| 11 | Downloads | Only completed + file-on-disk songs; plays offline with no network | ☐ |
| 12 | Library playlist | Owned and followed user playlists, plus saved company/creator playlists (same feed as the phone's Library tab); each opens its songs | ☐ |
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
| 23 | Tap a song in any list or a Home rail tile (Home, Recents, genre, Liked, Downloads, playlist, creator/album) | Now Playing opens at once and the song starts; Back returns to the list | ☐ |
| 24 | Tap a Recents song card | Now Playing opens once the song has been fetched; if the fetch fails nothing opens | ☐ |
| 25 | Deepest drill-down (Home See All → creator → song) | Now Playing opens (4 deep, inside `maxTemplateDepth`); Back walks the stack in reverse | ☐ |
| 26 | "Hey Siri, play X in Hallelujah" from a list, and from Now Playing itself | Song starts and Now Playing is on top; never two Now Playing templates in the stack | ☐ |
| 27 | Open Now Playing with a song playing | Button row is Like, Shuffle, Repeat (plus Sleep Timer on a plan that includes it) beside the transport controls; the top-right button reads "Queue" | ☐ |
| 28 | Shuffle button | Lit while the queue is shuffled; each tap toggles it and the song keeps playing; the phone's shuffle button follows, and a change made on the phone shows here | ☐ |
| 29 | Repeat button | Each tap cycles off → all → one: dark, lit, lit with the "1" glyph; the phone's repeat button follows | ☐ |
| 30 | Sleep Timer button | Opens 5–60 minute choices; picking one returns to Now Playing with the button lit; reopening marks the picked row and offers Turn Off Timer, which darkens the button. No button on a plan without the sleep timer | ☐ |
| 31 | Sleep timer runs out | Playback stops and the Sleep Timer button goes dark | ☐ |
| 32 | Queue button | "Queue" lists the playing song (with the playing dot) under Now Playing and the songs after it under Up Next, up to 100; an empty queue shows "Queue is empty" | ☐ |
| 33 | Tap a song in the Queue | Back to Now Playing and that song plays; the queue is not rebuilt, so Previous still reaches earlier songs; tapping the playing row only returns to Now Playing | ☐ |
| 34 | Song changes, or Shuffle is toggled on the phone, while the Queue is open | The list re-renders in place; the playing row stays on top | ☐ |
| 35 | Queue or Sleep Timer from the deepest drill-down (Home See All → creator → Now Playing → Queue) | Opens at depth 5; no `clientExceededHierarchyDepthLimit` crash | ☐ |

## Known gaps

- Siri "play X in Hallelujah": implemented via `SiriIntentsExtension` + `SiriPlayService`; needs a device test (CarPlay-only cold launch unverified).
- Recent *song* cards are resolved by searching their title (no song-by-id endpoint).
- Downloads does not live-refresh while open (Liked Songs does). Library playlists reload with the tab; a `playlistsChanged` post re-runs that reload, but nothing posts it yet.
- Auth guard is a simple signed-in check at connect time.
- Only a song started from CarPlay (list rows, rail tiles, Siri) opens Now Playing. A song started on the phone while connected leaves the car on whatever screen it was showing.
- Now Playing opens at tap time, so for the moment the stream takes to resolve it shows the previous track (or nothing).
- Shuffle, Repeat and Sleep Timer are custom image buttons driven by our own state. CarPlay's built-in shuffle/repeat buttons are not used: they read their state from `MPRemoteCommandCenter` shuffle/repeat commands, which `NowPlayingCoordinator` does not register.
- The Queue screen lists the playing song and what follows it (up to 100). Songs already played, reordering and removing stay on the phone.
- No playback-speed or Jam-style buttons: the app has no such feature.
