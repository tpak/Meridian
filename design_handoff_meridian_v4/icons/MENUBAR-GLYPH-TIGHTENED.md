# Design sync — menu-bar glyph tightened (UAT)

> ⚠️ **SUPERSEDED — historical.** This documents the *Midnight Sundial* menu-bar template, which has
> since been replaced by the partner's **Dial + Sun** glyph. See
> [`../CHANGES-FOR-DESIGN-PARTNER.md` §5b](../CHANGES-FOR-DESIGN-PARTNER.md) for what actually ships.

**Status:** shipped in local UAT `4.0.0-beta29`. **Deviates from `README-icons.md`** — please review.

## What changed and why
The handoff menu-bar template (`MenuBarIcon-template.svg`, 18pt raster = **33×18**, aspect ~1.83:1)
read **noticeably wider** than the surrounding system menu-bar items (teacup, Siri, Control Center,
etc.), leaving a wide buffer on either side. Menu-bar width is scarce on macOS, so per UAT feedback
we **tightened** it:

- **Shortened the horizon line** — the widest element — from `x 16→84` to `x 28→72` (kept the sun,
  the two rays, and the round caps).
- Cropped to a tight bounding box and rendered at **~17pt** tall (was 18pt).
- Result: **23×17 / 46×34**, aspect **~1.37:1** — closer to the neighbouring icons' footprint while
  staying recognizably the "Midnight Sundial."

Verified by screenshot in the live menu bar against its neighbours (balanced now).

## Implementation
- `Meridian/Media.xcassets/MenuBarIcon.imageset/` → `MenuBarIcon.png` (23×17) + `@2x` (46×34),
  `template-rendering-intent: template`. Drawn programmatically from the SVG geometry (sun circle +
  2 rays + shortened horizon), black-on-transparent.
- The original `MenuBarIcon-template.svg` is unchanged in this folder as the design master.

## For the design partner
If you'd prefer a different balance (e.g. a slightly wider horizon, or a redrawn glyph at this
aspect), send an updated `MenuBarIcon-template.svg` at roughly **~1.3–1.4:1** and we'll drop it in.
The app icon is unchanged from your handoff.
