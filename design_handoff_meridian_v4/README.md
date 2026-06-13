# Handoff: Meridian World-Clock Refresh (v4)

## Overview
Meridian is a **macOS menu-bar world-clock app written in Swift**. This package is the refreshed **v4** design, covering two surfaces:

1. **The menu-bar popover ("Daybreak")** — the panel that drops down when you click the menu-bar item. Lists tracked cities, shows day/night at a glance, and has a **time-travel scrubber**.
2. **The Settings window** — a Ventura-style sidebar window (Cities · Menu Bar · Appearance · Time Travel · General).

Plus the **menu-bar item** itself (the text shown up top).

---

## About the design files — READ FIRST
The files in this bundle (`*.dc.html`) are **design references built in HTML**. They are interactive prototypes that show the intended **look AND behavior** precisely. **They are not production code to ship.** Your job is to **recreate them natively in the existing Swift app** using its established patterns.

Two ways to use the HTML:
- **Open them in a browser** to see the live, interactive design (they self-render via the bundled `support.js`). Drag the scrubber, flip the Light/Dark and Home/Traveling/Day/Night demo toggles, double-click a time to edit it, etc.
- **Read the source** of each `.dc.html`. The markup is the exact layout; a `<script type="text/x-dc">` block near the bottom of each file holds the logic (the class `Component`) — this is where all the dynamic math lives (day/night, offsets, sky colors, scrubber). **Port that logic, don't reinvent it.**

> `support.js` is the prototype runtime — it lets the HTML render in a browser. **Do not port `support.js`.** It is irrelevant to the Swift implementation.

---

## Recommended implementation approach (Swift)
**Build native SwiftUI/AppKit — do not embed the HTML in a WKWebView.** A menu-bar utility depends on native hooks a web view can't reach. Suggested mapping:

| Design surface | Native construct |
|---|---|
| Menu-bar text | `NSStatusItem` with an `NSAttributedString` button title (the colored dot is a small inline image/attachment, or drop it for the Mono preset) |
| Popover ("Daybreak") | `NSPopover` hosting a SwiftUI root view |
| Settings window | SwiftUI `Settings` scene **or** an `NSWindow` using `NavigationSplitView` (sidebar + detail) |
| Light/Dark | System appearance (`@Environment(\.colorScheme)`); the prototype's toggle is just a demo affordance — real app follows macOS |
| "Currently in" timezone | `TimeZone.current` (auto-updates when the Mac's timezone changes while traveling) |
| "Home" timezone | A user-set preference (`TimeZone` stored in `UserDefaults`) |
| Start at Login | `SMAppService.mainApp` (ServiceManagement) |
| Float on top | `NSPopover.behavior = .applicationDefined` / detached panel that stays open |
| Live times | A 1s (or 60s, aligned to minute) `Timer`; recompute on `NSSystemTimeZoneDidChange` |

The **time-travel scrubber** is the only genuinely custom control. Try it natively first (a `DragGesture` over a `GeometryReader`-measured track). If it becomes painful, that single view *could* be an embedded web/Metal view — but everything else should be plain SwiftUI.

---

## Fidelity
**High-fidelity.** Colors, typography, spacing, and interactions are final. Recreate pixel-accurately with native equivalents. Exact values are in the **Design Tokens** section below and in the HTML source.

---

## How to drive this in Claude Code (for a backend engineer)
1. Open your **Meridian Swift repo** in Claude Code.
2. Add this folder to the repo (or point Claude Code at its path).
3. Prompt, roughly:
   > "These `*.dc.html` files in `design_handoff_meridian_v4/` are HTML design references for a redesign of this macOS menu-bar app. Read `README.md` and the `<script type="text/x-dc">` logic in each file. Implement them as **native SwiftUI** in this app, following the existing architecture. Start with the Daybreak popover. Do **not** embed the HTML in a web view."
4. Claude Code can open the HTML in a browser to see the live design and read the source for exact numbers.
5. **Iterate visually:** have it build & run, take a screenshot of the running app, and compare against the prototype; refine until they match.
6. **Going back and forth on design:** when you want a design change, come back to the design tool, I update the HTML, you drop the new files in, and Claude Code diffs + re-implements. The HTML is the single source of truth for "what it should look like."

> The design assistant cannot talk to Claude Code directly. This package **is** the interface between the two. Keep the HTML files as the canonical design spec.

---

## ⚠️ Dynamic behavior — be explicit (this is the important part)
The popover is **not static** — almost everything recomputes from a single clock value. Implement these rules exactly.

### A. The core model
- There is one **reference instant** = `now + travelOffset` (see scrubber). `travelOffset` is 0 when not time-traveling.
- Every city is a `TimeZone`. Its **local time** = the reference instant rendered in that zone.
- **"Currently in"** city = the zone matching `TimeZone.current` (auto-detected; changes when you travel). It is the **hero** at the top of the popover, labeled `<CITY> · CURRENT LOCATION` (or `· YOUR TIME` when you're home).
- **"Home"** city = a fixed user preference. When you are away from home, the home city appears as a normal row in the list **with a house badge (⌂)**.
- When current == home (not traveling): hero label is `· YOUR TIME`, and no row needs the house badge (home is the hero).
- **Offsets shown on each row are relative to the CURRENT location**, not UTC and not home. `offsetMinutes = city.utcOffset − currentLocation.utcOffset`. Display as `+11:30`, `−4:30`, `Your time` for the hero, etc. Append a day tag when the row's calendar day differs from the hero's: `· tmrw`, `· yest.`, `· +2d`, `· 2d ago`.

### B. Day/night per city (drives EVERYTHING visual)
For each city compute its local time in **minutes since local midnight** (`lm`, 0–1439) and its **sunrise/sunset** in the same units (`sr`, `ss`). Then:

```
phase(lm, sr, ss):
    if lm < sr - 50  OR  lm >= ss + 50 : "night"
    else if lm < sr + 50 :               "dawn"
    else if lm >= ss - 50 :              "dusk"
    else :                               "day"
```
(The 50 = a ±50-minute twilight window around sunrise/sunset.)

- **Glyph:** `phase == "night"` → **moon**; everything else → **sun**.
- This glyph appears on each city row, on the **hero**, and on the **scrubber handle** (the handle reflects the *current location's* phase). As you scrub, a city crosses sunrise/sunset and its sun flips to a moon (and vice-versa) — this must update live.
- **"Next sun event"** sub-label per row: if `lm < sr` → `↑ Sunrise <sr>`; else if `lm < ss` → `↓ Sunset <ss>`; else → `↑ Sunrise <sr>` (next day). Real app should compute true sunrise/sunset per coordinate/date; the prototype uses fixed per-city values.

### C. The hero sky (top section)
The hero's background gradient is chosen by the **current location's phase**:
```
night: linear-gradient(135°, #10122b → #2a2f5e)
dawn : linear-gradient(135°, #46406f → #ff9e6d)
day  : linear-gradient(135°, #34507f → #6f93c4)
dusk : linear-gradient(135°, #3a2f5e → #ff7a59)
```
Hero text is always white. The big time uses tabular figures. Sub-line = next sun event + weekday + date (e.g. `↓ Sunset 8:28 PM · Sunday 12 June`); on hover it swaps to `UTC−6 · Sunday 12 June` (hover-reveal — low priority, can be a tooltip).

### D. City row tint
Each row has a subtle gradient overlay keyed to its phase (warm for day/dawn/dusk, indigo for night), plus the sun/moon glyph in a colored disc. See tokens.

### E. Editable times (important)
Double-clicking any time (hero or a row) turns it into a text field. On commit (Enter/blur), parse the entered time and set `travelOffset` so **that city** reads the entered time, then **every other city + the hero + the scrubber recompute** from the new offset. Formula: `travelOffset += (enteredLocalMinutes − thatCityCurrentLocalMinutes)`, then clamp to the allowed range and snap to 15 min. Parser accepts `3:30 PM`, `15:30`, `3pm`, etc.

### F. Time-travel scrubber
- **Range:** ± "Future/Back" days from Settings → Time Travel (prototype: forward 14 days default, back 2 days; demo uses ±2 days). `travelOffset` is clamped to this window.
- **Drag** the handle to set `travelOffset` continuously; **snap to 15 minutes** (Settings → Time Travel → snap step: 5/15/30/60).
- **Arrows (‹ ›)** nudge by ± the snap step (15 min default) to the nearest boundary.
- The track shows **hour tick marks** plus **day-boundary markers** at the current location's local midnights, each labeled with the weekday/date; the marker for "today" is tinted with the accent.
- A **readout pill** shows the offset + resulting current-location time: `Now · 8:17 PM`, `+12:00 · Tue 12:17 AM`, `+2d · Wed 8:17 PM`. A **↺ Back to now** link appears when traveling (resets offset to 0).
- The handle is a **sun or moon** per the current location's phase (rule B).
- **Band (demo) note:** the live band gradient in the prototype is decorative; the *kept* design is the **tick ruler only** (no rainbow). The handle's sun/moon is the day/night cue.

### G. Menu-bar item
Shows only the **starred (favorite)** cities — no app name, no clock (macOS shows the system clock already). It grows to fit 1, 2, 3+ favorites. Each favorite = optional colored dot + label. Five density presets (set in Settings → Menu Bar), all selectable so the user can switch by how busy their bar is:
- **Compact:** `● IST 7:47 AM`
- **With day:** `● IST Mon 7:47 AM`
- **With date:** `● IST 7:47 AM 13 Jun`
- **Dense · 24h:** `● IST 07:47`
- **Mono · no dots:** `IST 7:47 AM` (plain text, no colored dot — matches the old app)
Underlying toggles: place name, day-of-week, date, 24-hour, color dots. The dot color = that city's per-city color (set in Settings → Cities).

---

## Screens / Views (layout reference — exact pixels in the HTML source)

### 1. Popover "Daybreak" — `Meridian — Daybreak.dc.html`
- Width **378px**, corner radius **18px**, 1px hairline border, large soft drop shadow, small notch at top pointing to the menu-bar item.
- **Hero** (top, ~padding 18–21px): uppercase eyebrow (`<CITY> · CURRENT LOCATION`, 11px/600, white 72%), big time **47px/640 tabular** with AM/PM at 18px, sub-line 12.5px white 82%, sun/moon disc 32px top-right.
- **City cards**: vertical stack, 8px gaps, each card radius **12px**, 11×14px padding; left = 23px sun/moon disc + name (14.5px/580) + next-sun sub (11.5px); right = time (20px/600 tabular) + offset (11px). Home row gets a `⌂` badge chip next to the name.
- **Scrubber**: centered readout pill; row of `‹` + tick track (height ~40px) + `›`; day-boundary labels under the ticks; `↺ Back to now` when traveling.
- **Footer**: `Settings` · `v4.0` · `Pin ▲`, 10–14px padding, top hairline.
- **Demo toggles above the popover (Dark/Light, Home/Traveling, Day/Night) are prototype-only — do NOT build them into the app.**

### 2. Settings window — `Meridian — Settings.dc.html`
- Window **748 × 744px**, radius 13px, traffic-light title bar (40px) with centered "Settings".
- **Sidebar** 198px: nav rows (icon chip + label), active row filled with the accent color.
- **Panes:**
  - **Cities** — "Locations" card (Home dropdown, Currently-in dropdown, Pin-to-top switch); search-to-add field; sort segmented (Time diff / Name / Label); list rows = drag handle, favorite star, per-city color dot (tap → palette), region/timezone + live time/offset, inline-editable label, remove ×. Current-location row is badged **Here** and pinned to top; home row badged **⌂ Home**.
  - **Menu Bar** — live preview strip; 5 density preset cards; fine-tune switches (place/day/date/24h/color dots); "Show Meridian in" (Menu Bar only / Dock & Menu Bar); "Float on top".
  - **Appearance** — Theme (Auto/Light/Dark); **Accent color** swatches (livery palettes — see disclaimer below); Time format (12/24); Day display (Relative/Actual/Date/Hide, **default Actual**); Sunrise/sunset switch (**default on**); Text size slider; live preview card.
  - **Time Travel** — Travel forward slider (1–30 days), Travel back slider (0–7 days), snap step (5/15/30/60 min), Show Time Scroller switch.
  - **General** — Start at login, Auto-install updates, Receive beta releases, Debug logging (switches); Check-for-updates frequency + Check Now; Export/Import Settings + Export Log (centered); About (version + GitHub links).

### 3. Menu-bar item
See **Dynamic behavior § G**.

---

## Design Tokens

### Color — popover/app surfaces
| Token | Dark | Light |
|---|---|---|
| surface (popover) | `#171922` | `#fbfbfd` |
| text | `#f1f1f5` | `#1a1b20` |
| text secondary | `rgba(235,235,245,.55)` | `rgba(60,60,67,.6)` |
| text tertiary | `rgba(235,235,245,.4)` | `rgba(60,60,67,.45)` |
| hairline/border | `rgba(255,255,255,.08)` | `rgba(0,0,0,.07)` |
| canvas (behind popover) | `#0e0f13` | `#e9eaee` |

### Color — Settings window
surface `#1e2024` (dark) / `#ececef` (light); sidebar `#191b1f` / `#e7e7ea`; titlebar `#26282d` / `#e3e3e7`; card `#26282d` / `#fbfbfd`.

### Accent (user-selectable "livery" palettes — default McLaren)
`McLaren #FF7A00` · `Ferrari #E8002D` · `Mercedes #00A19C` · `Red Bull #1E41FF` · `Williams #37BEDD` · `Alpine #FF5FA2` · `Graphite #7C8493` · `Indigo #6366F1`. The chosen accent fills active toggles, selected nav, the scrubber "NOW"/markers, etc. (Daybreak's warm scrubber/handle accent is a gold `#ffc24d` dark / `#c98a2a` light.)

> **F1 disclaimer (must ship in Settings → Appearance, under the swatches):** "Palette names & colors are stylized tributes for personalization only. Team names and liveries are trademarks of their respective Formula 1 teams — all rights reserved. Meridian is not affiliated with or endorsed by them."

### Sun / Moon discs
- Sun: radial gradient `#f2cf86 → #dd9e30` (toned-down amber), faint glow `~0 0 7px rgba(216,158,48,.3)`.
- Moon: radial gradient (offset center) `#dfe1f8 → #8b90e8`, faint indigo glow.

### Hero sky gradients
See **Dynamic behavior § C**.

### Sky-color ramp (only needed if you render a sky gradient anywhere)
Piecewise-linear interpolation, hour-of-day → RGB. Stops:
`0→(27,33,56)`, `5→(27,33,56)`, `6→(44,40,74)`, `6.8→(120,96,120)`, `7.6→(178,150,150)`, `9→(150,178,210)`, `12→(166,196,226)`, `15→(150,178,210)`, `16.5→(184,160,150)`, `18.2→(178,120,116)`, `19.6→(110,90,124)`, `21→(48,46,80)`, `22.5→(27,33,56)`, `24→(27,33,56)`.

### Typography
System font (**SF Pro** via `system-ui`). Times use **tabular figures** (`monospacedDigit()` in SwiftUI). Key sizes: hero time 47/640; city time 20/600; row name 14.5/580; labels 11–12.5; eyebrow 11/600 uppercase tracked. Mono numerals for the Console-style menu-bar text use `SF Mono`/`monospaced`.

### Radii / spacing
Popover 18 · cards 12 · settings window 13 · controls/segments 7–9 · switches 22px tall (38px wide). Card gap 8. Form-row label column ~150px right-aligned.

---

## Assets
- `reference-old-app.png` — screenshot of the **old (v3.1.2)** app, for before/after context only. Not part of the new design.
- App icon: not redesigned here (keep existing).
- No bitmap assets are required by the new design — all glyphs are simple shapes (discs, ticks, chevrons) and SF text. Use **SF Symbols** for the gear/pin/search/star/house/chevrons in the native build.

---

## Files in this bundle
- `Meridian — Daybreak.dc.html` — the menu-bar popover design + all dynamic logic (hero, cities, day/night, offsets, editable times, scrubber, menu-bar density presets). **Primary file.**
- `Meridian — Settings.dc.html` — the Settings window design + logic (cities mgmt, menu-bar presets, appearance, time travel, general).
- `support.js` — prototype runtime so the HTML renders in a browser. **Reference only — do not port.**
- `reference-old-app.png` — old app screenshot.
- `README.md` — this document.

To view a design: open the `.dc.html` file in a modern browser (Chrome/Safari). Read the `<script type="text/x-dc">` block at the bottom for the exact logic.
