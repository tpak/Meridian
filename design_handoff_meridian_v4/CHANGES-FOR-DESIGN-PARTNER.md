# What we changed in Meridian v4

This document records everything the shipped Meridian v4 app **adds to** or **changes from** the
original v4 handoff (`README.md` + the `*.dc.html` prototypes). It's shared so your reference designs
reflect what actually shipped.

**This is informational — for your records. No action or sign-off is needed.** Where we diverged from
the prototype we've noted *why*, so the intent is clear. Screenshots of every page of the shipped app
are in [`screenshots/`](screenshots/).

> **Legend:** **Added** = new since the handoff · **Changed** = ships differently than the prototype.

> **Contents**
> - **§1 — Added since the handoff**
> - **§2 — Changed from the original spec** (by surface)
> - **§3 — Copy all city times + Float / draggable popover**
> - **§4 — Stacked menu-bar layout**
> - **§5 — Icons (app icon + menu-bar glyph)**
> - **§6 — Page screenshots**

All items were verified against the shipping code (4.0.0-beta3x).

---

## 1. Added since the handoff

Net-new features and surfaces that weren't in the original prototypes.

**Daybreak popover**
- **Copy all city times** — a copy icon (`doc.on.doc`) in the footer copies every city's name + time
  to the clipboard, flipping to an accent-tinted checkmark for ~1.4s. Restored from v3. Detail in §3.
- **Float + draggable popover** — the footer's old "Pin" is now **"Float"**, and when floating the
  popover becomes a free-floating window you can drag anywhere; it remembers where it's parked.
  Restored from v3. Detail in §3.
- **Empty-state message** — with no tracked cities the popover shows *"Add places in Settings to see
  them here."* (the prototype always rendered demo cities, so there was no empty state).

**Settings → Cities** *(see `screenshots/settings-cities.png`)*
- **Search-to-add results dropdown** — typing in the add-city field shows an inline ranked results
  list: each row has a kind icon (`mappin.and.ellipse` for cities, `globe` for timezones), a title,
  and an accent-tinted highlight. The prototype had a bare input with no results UI.
- **Keyboard + hover navigation** — arrow keys move a highlight through the results, Return adds the
  highlighted one, Escape clears the query, and hover drives the same highlight.
- **Sort-direction toggle** — re-tapping the active sort segment reverses direction, shown by an
  up/down caret on that segment.

**Settings → Menu Bar** *(see `screenshots/settings-menubar.png`)*
- **Stacked preset** — a 6th menu-bar preset (city name over time, two lines) so more favorites fit a
  narrow/notched bar. Default off; restores the pre-v4 two-line layout. Detail in §4.

**Settings → Appearance** *(see `screenshots/settings-appearance.png`)*
- **Text-size percentage readout** — a live "100%" label sits to the right of the Text size slider.

**Settings → General** *(see `screenshots/settings-general.png`)*
- **Global keyboard shortcut recorder** — a "Global shortcut" row (under Debug logging) records a
  hotkey that toggles the popover from anywhere. The v4 move to SwiftUI Settings had dropped the v3
  global hotkey; this restores it. It currently uses the legacy AppKit recorder control (rounded
  bezel, "Click to Record Shortcut"), not the v4 visual language.

---

## 2. Changed from the original spec

Grouped by surface. Each row: the original prototype, what shipped, and why.

### Daybreak popover  *(see `screenshots/popover.png`, `screenshots/hero.png`)*

| Area | Original spec | Shipped v4 | Why |
|---|---|---|---|
| **Time-travel scrubber range** | Spans the Travel forward/back **day window** (14 fwd / 2 back) with dated day-boundary markers | Fixed to **~2h back / 12h forward**; the Settings day sliders don't drive it | Interim hour-scale window; the day-window model was deferred. |
| **Scrubber day-boundary markers** | Dated midnight markers along the track, "today" accent-tinted | A plain tick comb — no dated markers, no date labels, no accent tint | Simplified ruler for the hour-scale window. |
| **Scrubber interaction** | Clicking anywhere on the track jumps the handle there | Drag-only (a deliberate drag of ≥5pt scrubs; a plain click does nothing) | Prevents stray clicks from silently entering time-travel. |
| **Handle mapping** | Linear across a symmetric range, so "now" sits centered | "Now" is pinned to the visual center; past compresses into the left half, future into the right (non-proportional) | Keeps "now" centered on the asymmetric −2h..+12h range. |
| **Scrubber visibility** | Always shown | Hidden when Settings → Time Travel → "Show Time Scroller" is off (popover collapses to hero + cities + footer) | Honors the existing show/hide toggle. |
| **Time-travel persistence** | Travel delta persists across interactions | Resets to "Now" each time the popover opens | The hero must match the live system clock on open. |
| **Traveled minute grid** | Snap the offset to 15 min | Traveled times land on a clean quarter-hour grid frozen at travel-start | Cleaner displayed minutes while traveling. |
| **Scrubber sky band** | A decorative live sky-color band behind the ruler | No band — tick ruler only | Per the prototype's own §F note ("kept design is the tick ruler only, no rainbow"). |
| **Footer version** | Literal "v4.0" | The live version string (e.g. `v4.0.0-beta33`) | Shows the actual build. |
| **Popover drop shadow** | Large soft shadow (`0 28px 70px`) | Lighter, window-like shadow (radius 18, y 8) | The large shadow read heavy next to standard macOS windows. |
| **Popover top notch** | A small notch pointing at the menu-bar item | Removed | Read as a stray artifact, especially while floating away from the bar. |
| **Footer "Pin"** | `Pin ▲` / `Unpin ▼` | `Float ▲` / `Unfloat ▼` + draggable floating popover | "Float on top" matches the wording used in Settings → Menu Bar. Detail in §3. |

### Settings → Cities  *(see `screenshots/settings-cities.png`)*

| Area | Original spec | Shipped v4 | Why |
|---|---|---|---|
| **Drag-to-reorder handle** | A ⠿ grab handle on each row | Removed — rows start at the favorite star; ordering is via the **Sort** control | Drag-reorder wasn't carried into v4. |
| **"Currently in" control** | An interactive dropdown (chevron + options) | A read-only text box | The current location is auto-detected; it isn't manually overridden here. |
| **Home control glyph** | Leading house glyph: `⌂ {label}` | Label text only, no ⌂ prefix | — |
| **Non-removable row** | The **Home** row can't be removed | The auto-detected **Current-location** row is the protected one; the home row can be removed while traveling | The current location is the one that must always exist. |
| **City row color-dot ring** | Window-colored 2px border + a color-matched outer ring | A neutral 1px outline | Simplified treatment. |
| **Inline label field width** | 116px | 92px | — |

### Settings → Menu Bar  *(see `screenshots/settings-menubar.png`)*

| Area | Original spec | Shipped v4 | Why |
|---|---|---|---|
| **Live preview strip** | Built from the user's real favorites, each dot in that city's color | A fixed two-chip sample (IST teal + Denver red) | Representative sample rather than live data. |
| **Menu-bar dot** | Described as a small inline image | The live menu-bar dot is a text bullet (`U+25CF`) sized to the font; the Settings preview uses a 5px circle | Implementation detail; the two surfaces don't share one dot primitive. |
| **Preset card sample** | Label over a left-aligned sample, single line | Sample is right-aligned and each card reserves two lines | So the two-line Stacked card doesn't enlarge its grid row. |
| **Color dots** | Dot dropped only for the Mono preset | A standalone "Color dots" toggle (any preset can drop dots); the Stacked layout never draws one | More flexible. Detail in §4. |

### Settings → Appearance  *(see `screenshots/settings-appearance.png`)*

| Area | Original spec | Shipped v4 | Why |
|---|---|---|---|
| **Accent palette + default** | 8 swatches (McLaren default · Ferrari · Mercedes · Red Bull · Williams · Alpine · Graphite · Indigo) | **11 F1-team liveries** (Alpine, Aston Martin, Audi, Cadillac, Ferrari, Haas, McLaren, Mercedes, Racing Bulls, Red Bull, Williams); default **Aston Martin**; no Graphite/Indigo; revised hex values | Expanded the livery set. |
| **Day display default** | Actual | **Relative** | — |
| **Sunrise/sunset default** | On | **Off** | — |
| **Theme default** | Follow macOS (Auto) | **Light** | The Theme control still offers Auto/Light/Dark. |
| **Toggle control style** | Accent-filled switches | Custom accent-tinted switches that track the live accent | Matches the prototype's accent-filled toggles with a custom control. |
| **Preview-card background** | Fixed warm gold/amber gradient | Follows the live accent (12%→4% opacity) | Ties the preview to the selected livery. |
| **Preview-card city dot** | Denver's per-city color (red) | The global accent | — |
| **Accent swatch ring** | The swatch's own color | The global accent | — |

### Settings → Time Travel & General  *(see `screenshots/settings-timetravel.png`, `screenshots/settings-general.png`)*

| Area | Original spec | Shipped v4 | Why |
|---|---|---|---|
| **Time Travel day sliders** | "Travel forward / back" bound the scrubber range | Currently inert — the scrubber range is fixed (see Daybreak above); the sliders are shown but not yet wired | Pending the day-window scrubber rework. |
| **Travel forward default** | 14 days | 6 days | Carries the existing app-wide default. |
| **Receive beta releases default** | On (in the prototype state) | Off | Shipping beta-on to everyone isn't the default we want. |
| **Export Log button** | Always enabled | Disabled until Debug logging is on | Export Log is only meaningful when logging is on. |
| **Command buttons + About links** | Bordered command buttons; About links as plain accent text | All use a shaded button style (subtle fill + hairline border) | The system bordered/plain-link styles read nearly invisibly on the dark Settings canvas. |
| **Check-for-updates layout** | Frequency segment and "Check Now" on one row | "Check Now" on a second row under the segment | Keeps it off the right edge. |

---

## 3. Copy all city times + Float / draggable popover

Two footer behaviors carried over from v3 that the original handoff didn't cover. Both shipped in v4.

### 3a. Copy all city times

A copy icon in the footer puts **every tracked city's current time** on the clipboard as text — for
pasting a quick "here's what time it is everywhere" list into a message, calendar invite, or email.

The Daybreak footer is now:

```
┌──────────────────────────────────────────────────────────────┐
│  Settings   ⧉            v4.0.0            Float ▲             │
└──────────────────────────────────────────────────────────────┘
   └ text btn └ copy        └ version (center)   └ float text btn
```

- **Placement:** in the left group, immediately right of **Settings** (mirrors v3's "gear + copy").
- **Icon:** SF Symbol `doc.on.doc`, 12pt medium, icon-only, color `palette.foot`.
- **Tap feedback:** flips to a `checkmark` for ~1.4s tinted with the Daybreak accent gold, then reverts.
  No toast or modal.
- **Tooltip / a11y:** "Copy all city times".

**Behavior:** copies the hero (current location) first, then each city card top-to-bottom — exactly the
popover order. It reflects the scrubber (if you've traveled, the copied times are the displayed times)
and honors the 12h/24h setting. Format is one city per line, `{City name} — {time}{ period}`:

```
Melbourne — 10:47 PM
Djibouti — 3:47 PM
Paris — 2:47 PM
Denver — 6:47 AM
San Francisco — 5:47 AM
```

(v3 joined everything onto one line with ` / `; v4 uses one city per line for readability.)

### 3b. Float (was "Pin") + draggable floating popover

- **Rename:** the footer's right-hand button reads **`Float ▲`** when not floating and **`Unfloat ▼`**
  when floating — matching "Float on top" in Settings → Menu Bar. Tooltip: *"Float on top (drag to
  move)"* / *"Stop floating on top."*
- **Draggable:** when floating, the popover stays open, floats above other windows, and can be dragged
  anywhere by its background/chrome (the hero area and the padding around the cards). Interactive
  surfaces — scrubber, footer buttons, city rows, the hero inline time-edit — keep working; only
  non-interactive background starts a drag. There's no title bar or drag handle; the whole background
  is the drag surface.
- **Persistence:** it remembers where it's dragged across launches, clamped onto the current screen so
  a disconnected display can't strand it off-screen. When floating is off (default), the popover is
  anchored under the menu-bar item and dismisses on click-away, as before.

---

## 4. Stacked menu-bar layout  *(issue #142; see `screenshots/settings-menubar.png`)*

The original handoff specified the menu-bar item as **single-line only** (five density presets). v4 adds
an opt-in **two-line "stacked"** layout (city name over the time), default **off** — every existing
user keeps the single-line item.

**Why:** a single-line `● IST 7:47 AM` item is wide; with 3–4 favorites on a 13" MacBook with a notch,
the rightmost cities get clipped. The two-line layout stacks name over time, roughly halving the width
per city. It restores the pre-v4 layout (the renderer was never deleted, just behind a flag) as a
runtime, user-selectable option.

**What shipped:**

```
Single-line (default)                Stacked (the 6th preset)
┌────────────────────────┐           ┌──────────┐┌──────────┐
│ ● IST 7:47 AM  ● DEN…  │           │   IST    ││   DEN    │
└────────────────────────┘           │ 7:47 AM  ││ 8:17 PM  │
                                      └──────────┘└──────────┘
```

- **Where:** Settings → Menu Bar → a 6th preset card, "Stacked", after "Mono · no dots".
- **Type/metrics:** name line = SF semibold 10pt, time line = SF regular tabular 10pt, natural line
  height, 50/50 split.
- **Color dots:** dropped in stacked mode (the two-line layout doesn't draw one), and the Settings
  live-preview omits the dot in this mode so the preview matches reality.

This is an interim engineering restore of the legacy layout — it isn't yet styled to the Daybreak
visual language.

---

## 5. Icons — app icon + menu-bar glyph

### 5a. App icon — "Midnight Sundial"

The original handoff said to keep the existing app icon. We instead shipped a new full-color app icon,
**"Midnight Sundial"** — a warm sun seated as the 12-o'clock mark of a fan of hour ticks, on a deep
midnight-navy sky, above a horizon line — across all macOS sizes. Palette: sky `#0d1538 → #26407a`,
sun radial `#fff7df → #ffd373 → #f7a838`, ticks `#ffce6e`, horizon `#ffffff @50%`. Vector master:
`icons/AppIcon-source.svg`.

### 5b. Menu-bar glyph

The monochrome menu-bar template (shown only when no city is starred) is a **template image** — pure
black on transparent; macOS tints it (white on dark bars, black on light, accent when open). The
artwork is **currently being refreshed with you**; the shipped glyph is interim until the new mark
lands.

> Earlier icon notes in `icons/README-icons.md` ("Icon 2 — Menu-bar item") and
> `icons/MENUBAR-GLYPH-TIGHTENED.md` describe a now-retired menu-bar mark and are kept only as history.

---

## 6. Page screenshots

Screenshots of the shipping app, in [`screenshots/`](screenshots/):

| File | Page |
|---|---|
| `hero.png` | Menu-bar item + the open Daybreak popover |
| `menu-bar-item.png` | Starred cities in the macOS menu bar |
| `popover.png` | The Daybreak popover — hero + city cards + footer |
| `time-travel.png` | The popover mid-travel (offset pill + "Back to now") |
| `settings-cities.png` | Settings → Cities |
| `settings-menubar.png` | Settings → Menu Bar (preset grid + live preview) |
| `settings-appearance.png` | Settings → Appearance (accent palette + preview) |
| `settings-timetravel.png` | Settings → Time Travel |
| `settings-general.png` | Settings → General |

---

*Maintainers: this is the single consolidated record of how shipped v4 differs from the handoff. When
you add a feature that isn't in the handoff, or ship something different from the prototype, add it
here and refresh the screenshots so this stays the accurate picture of the product.*
