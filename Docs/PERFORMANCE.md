# Performance (T72)

**Status: protocol and budgets written; no numbers measured yet.** Instruments
needs a Mac and a physical ProMotion device. Fill the tables in; do not tick
the "zero hitches" criterion from reading code.

## Budgets

| Metric | Budget |
| --- | --- |
| Frame time while scrolling (ProMotion) | ≤ 8 ms (120 fps) |
| Animation hitch ratio, home / search / library / playlist | 0 ms/s |
| Cold start to first interactive Home frame | ≤ 1.5 s (release build, mid-range device) |
| Memory ceiling, 30 min of playback + browsing | ≤ 350 MB |
| Battery, 1 h background playback | ≤ 4 % |

## How to measure

1. Profile a **Release** build on device: *Product → Profile*.
2. **Animation Hitches** template: scroll Home (top → bottom → top), Search results,
   Library, a 100-song playlist. Record the hitch ratio per screen.
3. **App Launch** template: cold start with a signed-in account, 5 runs, take the median.
4. **Allocations + Leaks**: play 20 songs, open/close the full player 10×, open every
   sheet once. The graph must return to baseline.
5. **Energy Log**: 30 min playback with the screen locked.
6. **CarPlay**: connect in the simulator, open every tab and drill 3 levels; check main-thread
   time on connect (`CarPlayController.start()` must not block).

## Results

| Screen | Hitch ratio | Frame p95 | Notes |
| --- | --- | --- | --- |
| Home | _not measured_ | | |
| Search | _not measured_ | | |
| Library | _not measured_ | | |
| Playlist detail | _not measured_ | | |
| Full player | _not measured_ | | |
| Cold start | _not measured_ | | |

## Design decisions already made for smoothness

- Lists are `LazyVStack`/`LazyHStack` with stable `id`s (`Song.id`, `Playlist.id`).
- Artwork goes through `ArtworkImageCache` (downsampled to display size, in-flight de-duplicated,
  200-item `NSCache`); CarPlay adds a disk tier (`CarPlayArtworkLoader`).
- Decoding, disk and image work run off the main actor (actors / `Task`s in the data layer).
- Glass surfaces go through the single `GlassSurface` primitive; no ad-hoc blur over scrolling content.
- The sleep-timer badge refreshes once a second through `TimelineView`, only while a timer runs.

## Suspects to check first

- `HomeView` rails with many cards (image prefetch window).
- `FullPlayerView` re-rendering on every position tick (`AudioEngine.currentPosition` updates at 2 Hz).
- `SongMenuButton` instantiates a `@State` + sheet modifier per row — confirm it is free at 100+ rows.
