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

## Wide windows: iPad, foldables, Mac (D20)

Layout follows the live window width (`App/DesignSystem/Layout/AdaptiveLayout.swift`), so every
check below is "resize, then look". Phone width (≤ 440pt) must be unchanged from Flutter.

Devices / windows to cover: iPhone (regression), iPad mini portrait, iPad Pro 13" portrait and
landscape, iPad Split View ½ and ⅓ plus Slide Over, Stage Manager window dragged from narrow to
wide, Mac "My Mac (Designed for iPad)" window resized from its minimum (390 × 640) to full screen.

- ☐ iPhone regression: Home, Search, Library, player, Settings and sign-in look identical to the
  previous build (spot-check against screenshots).
- ☐ Resizing never resets scroll position, playback, or the open tab, and never shows a frame of
  the phone layout stretched across a wide window after the first launch frame.
- ☐ Mini player stays a centred pill (≤ 600pt) and still swipes to skip / taps to expand.
- ☐ Full player, portrait or narrow window: centred column, artwork never pushes the transport
  controls off screen. Wide landscape window: artwork and controls on the left, lyrics/credits/
  "More like this" scroll on the right. Rotate mid-song: no restart, no stuck zoom transition.
- ☐ Grids (Browse genres, episodes, section "see all", languages, chapters) gain columns as the
  window widens; tiles stay roughly phone-sized.
- ☐ Nothing is sized from the screen: artwork headers, trending carousel, share cards and verse
  cards stay a sensible size at 1366pt.
- ☐ Settings, profile, support, subscription, AI chat, Bible reader and lyrics read as a centred
  column (~640pt); sign-in and OTP as a narrower form column. Scrolling works with the pointer
  over the side gutters.
- ☐ Sheets on iPad/Mac (form-sheet cards) lay out for the sheet's width, not the window's.
- ☐ Mac: the window cannot be dragged below one phone screen; sign-in (Apple, Google, phone
  OTP), purchases, downloads, background audio and push all work. Open a second window
  (File ▸ New Window) and confirm deep links and push taps still route correctly.
- ☐ Tab bar on iPadOS 18+/Mac sits at the top: headers drawn by Home, AI and Bible are not
  covered by it.
