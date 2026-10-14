# Accessibility (T73)

**Status: partially implemented, not audited with VoiceOver.** Run the checklist
on a device before relying on any of it.

## Implemented in code

- **Reduce Transparency**: `GlassSurface` renders an opaque elevated surface (with a hairline
  stroke) when the setting is on. On iOS 26 the system `glassEffect` adapts itself.
- Icon-only buttons added in this port carry `accessibilityLabel`s: song "More", sleep timer,
  "Turn off sleep timer", library add/remove, content-menu "More".
- Minimum 48 pt tap targets for menu rows (`Spacing.minTapTarget`).
- Dynamic Type: all text uses `Typography` tokens (system font), never fixed point sizes in views
  — except a few SF Symbol `font(.system(size:))` icon sizes.

## Checklist (not yet run)

| Flow | VoiceOver | Dynamic Type XXL | Reduce Motion | Reduce Transparency |
| --- | --- | --- | --- | --- |
| Sign in (phone / email / social) | ☐ | ☐ | ☐ | ☐ |
| Home → play a song | ☐ | ☐ | ☐ | ☐ |
| Full player (transport, seek, favourite) | ☐ | ☐ | ☐ | ☐ |
| Song menu → every row | ☐ | ☐ | ☐ | ☐ |
| Search → play | ☐ | ☐ | ☐ | ☐ |
| Library / Downloads | ☐ | ☐ | ☐ | ☐ |
| Subscription purchase | ☐ | ☐ | ☐ | ☐ |
| Read (Bible) | ☐ | ☐ | ☐ | ☐ |
| AI chat | ☐ | ☐ | ☐ | ☐ |

## Known gaps

- Reduce Motion is not yet honoured by `MarqueeText`, the sleep-badge ring or the AI orb.
- Custom controls (seek bar, marquee) need explicit `accessibilityValue`/`adjustableAction` review.
- Contrast of `textTertiary` on glass has not been measured.
