# IPRS play-count tracking — progress (native iOS, branch `main`)

Owner: Sonu. Started 2026-10-23. The server contract, the IPRS research and
every assumption are in `gs_nh_backend` (branch `dev`)
`docs/IPRS_PLAY_COUNT_PROGRESS.md`. The Flutter app (`ghallelujah_app`, branch
`ai`) has the same fixes in `docs/IPRS_PLAY_COUNT_PROGRESS.md`; this port now
matches it.

> **Uncompiled.** Written in a Linux container with no Xcode or Swift
> toolchain. Not built, not run. Sonu must build and verify on a device
> (checklist at the bottom).

## Status

| # | Task | State |
|---|------|-------|
| I1 | Session END rows reach the server (they were all discarded) | Done, uncompiled |
| I2 | Batches over 50 sessions no longer lose sessions | Done, uncompiled |
| I3 | Every loop of a song is its own play session (incl. repeat-one) | Done, uncompiled |
| I4 | Offline (downloaded-file) plays flagged `is_offline` | Done, uncompiled |

## What was wrong

### I1 — no iOS session ever recorded its end

The recorder queues a session as two rows: START (song, start time) and END
(`ended_at`, end position, loop count). The production backend dropped any
session row without `song_id` + `started_at` **before** looking it up, so
every END row was discarded. Plays still counted eventually (via the
6-hour force-process sweep and the `end` playback event), but late, and
`loop_play_number` / `is_suspected_fraud` never arrived.

Fixed on both sides, so it works against the current production server too:
- `PlaybackSessionEndEvent` now carries `song_id` and `started_at`.
- `PlaybackAnalyticsUploader` merges START + END rows of the same
  `session_id` into one row before sending.
- The backend (`dev`) now merges and accepts end-only rows as well.

### I2 — up to 450 sessions per sync silently lost

`AnalyticsSyncEngine` uploads up to 500 queue items per request; each item may
be a session START, a session END, or an event. The production server sliced
requests to 50 sessions / 500 events **and still answered 200**, and this
client deletes the whole batch on 200. An offline listener easily queues more
than 50 session rows, so everything past the 50th was gone for good.

Fix: the uploader splits one batch into as many requests as needed
(≤50 session rows, ≤500 events each) and reports success only if all of them
succeed. A partial failure re-sends the batch next time; the server absorbs
the duplicates (`session_id` / `event_id` keys). The backend now refuses
oversized requests with 413 instead of truncating.

### I3 — loops were one session (creators lost the plays)

`recordLoopRestart()` only bumped a counter on the open session, and
repeat-one had no hook at all (`QueueController.onLoopRestart` only fires for
a one-song queue under repeat-all). A song looped five times reached the
server as one session — one play at most.

Fix (`PlaybackAnalyticsRecorder`):
- A loop ends the current session at its final position and starts a **new
  session** for the same song with `loop_play_number = n` on the START row.
- Repeat-one is detected in the existing 2-second progress poll, the same way
  the Flutter bloc does it: playhead went from ≥85% back to <5 s while
  playing, with no seek in between.
- Double reports (hook + poll for the same wrap) are ignored for 5 s after a
  session starts; `songID` is restored synchronously so the engine's re-play
  can't start a second session.
- Loop restarts skip the recently-played sync and playlist-progress step.
- How many loops COUNT is the backend repeat cap's call
  (`maxCountedPlaysPerUserPerDay`, default 3/user/song/IST day). The 20/day
  client threshold only sets the `is_suspected_fraud` hint.

### I4 — offline plays

`startSession` asks `engine.localFileURLProvider` (the same lookup the engine
uses to choose the downloaded file over the stream) and sends `is_offline`
1 / 0 on the START row. The backend stores it as `PlaybackSession.isOffline`
and reports offline plays separately to IPRS.

The analytics queue itself (GRDB `AnalyticsEventStore`) was already durable
across launches and offline periods; no change there.

## Known gaps not fixed

- Same as Flutter: rows queued while logged out / on another account upload
  under whoever is signed in at sync time.
- `PlaybackTrackingEvent.networkState` comes from a second reachability
  monitor in the recorder — fine, but it is a different instance from the UI's
  `NetworkStatusStore`; they can disagree for a moment at a transition.
- A wrap the 2-second poll misses (track under ~14 s, or paused exactly at
  the boundary) is still one session.

## Sonu — verify on device

1. Build. New/changed: `PlaybackAnalyticsEvents.swift`,
   `PlaybackAnalyticsUploader.swift`, `PlaybackAnalyticsRecorder.swift`.
2. Play 3 songs and wait for a sync (or log out to force one): every session
   in the DB has `endedAt` set within minutes, not 6 hours.
3. Repeat-one a song for 3 passes: 3 sessions, `loopPlayNumber` 0,1,2.
4. Airplane mode, play a downloaded song, come back online: `isOffline=true`.
5. Queue a large offline backlog (60+ songs) then reconnect: all sessions
   arrive (check the count in `/admin/play-counting`).
