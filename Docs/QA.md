# Manual QA

Automated tests cover pure logic (`Tests/`). These flows need a device or simulator and are
**not yet run**; tick them as they pass.

- ☐ Sleep timer: start 5 min, lock the phone, playback pauses and the player closes on unlock.
- ☐ Sleep timer is premium-only: a free account is sent to the plans screen.
- ☐ Song menu from the player and from a creator/genre/search row: favourite, add to playlist,
  add to queue (already queued → opens the queue), go to artist, credits, download states, report, stop.
- ☐ Report: blank reason is refused; success stops playback and closes the player.
- ☐ Playlist detail: save/remove from library (removal asks to confirm), menu → add to queue, share.
- ☐ Creator profile menu: share, add to queue, follow state stays in sync with the header chip.
- ☐ Premium gating: downloads and Audio Quality hidden/redirected for free users; ads never shown to premium.
- ☐ CarPlay: see `Docs/CARPLAY.md`.
