# Changes to share with the design partner

A running list of where the shipped v4 app **adds to** or **diverges from** the handoff spec (`README.md` + the `*.dc.html` prototypes). The HTML is the canonical design; this doc is the back-channel for "here's what we built/changed — confirm it, or update the design." Keep it current as we ship.

> Status legend: **Added** = new since the handoff · **Diverges** = ships differently than the spec; please confirm intended or update the HTML.

---

## Added since the handoff

### Global keyboard shortcut recorder — Settings → General  *(Added, PR #174 / issue #168)*
The v4 redesign moved Settings to SwiftUI and, in doing so, dropped the **global hotkey** that toggles the Daybreak popover (it only existed in the old storyboard Settings). We've **restored it** as a new **"Global shortcut"** row in the **General** pane (under the Debug-logging toggle), matching the `FormRow` layout: a 150px label + a recorder control + the note "Open Meridian from anywhere."
- **It's not in the handoff** — the spec's General pane is login / updates / beta / debug / frequency / backup / about, with no shortcut control.
- **Design ask:** the recorder currently reuses the **legacy AppKit button** (rounded bezel, "Click to Record Shortcut" / shows e.g. `⌘⌥M`), which is *not* in the v4 visual language. If you want it styled to match (e.g. a chip/segment that matches the accent + control radii), please add it to the Settings HTML and we'll re-skin.

### Stacked menu-bar preset  *(Added — see [`STACKED-MENUBAR.md`](STACKED-MENUBAR.md))*
A **6th** menu-bar preset, "Stacked" (city name over time, two lines), added beyond the spec's five density presets so more favorites fit a narrow/notched bar. Currently an interim restore of the pre-v4 two-line layout, not yet fully styled to v4.

### Copy-all-cities footer action  *(Added — see [`COPY-ALL-CITIES.md`](COPY-ALL-CITIES.md))*
A copy icon in the popover footer that copies every city's name + time to the clipboard.

### Menu-bar glyph tightening  *(Added — see [`icons/MENUBAR-GLYPH-TIGHTENED.md`](icons/MENUBAR-GLYPH-TIGHTENED.md))*
Adjustments to the menu-bar sundial glyph spacing.

### New menu-bar icon "Dial + Sun" + size adjustment  *(Added, PR #177 — source in [`icons/menubar-dialsun/`](icons/menubar-dialsun/))*
Adopted the partner's new **Dial + Sun** template glyph (the monochrome icon shown when no cities are starred). **Size feedback:** as delivered, the glyph filled only **~75% of its canvas** (≈30% internal padding), so in the menu bar it rendered noticeably smaller than the neighboring system/app icons. We re-rendered the shipped asset with the glyph scaled to fill **~92%** of the canvas as an interim fix. **Ask:** please bake the larger glyph (less padding, ~90% fill — the dial circle close to the icon's edges) into the master SVG/PNGs and resend, so we ship your exact artwork instead of our rescale.

---

## Diverges from the spec — please confirm intended or update the HTML

These were verified against the shipping code (4.0.0-beta3x). Each may be a deliberate product call — flagging so design and build agree.

| Area | Handoff spec says | Ships as | Note |
|---|---|---|---|
| **Time-travel scrubber range** | §F: drag spans the **Travel forward/back day window** (forward 14 default, back 2) with day-boundary markers | Live drag scrubber is **fixed to ~2h back / 12h forward**; the Settings day sliders bound the *typed-time* jump, not the drag | Biggest behavioral gap. Interim by design (a code note says the day sliders "will be reworked to hour-scale to drive this"). Confirm the intended scrubber model. |
| **Accent palette** | McLaren · Ferrari · Mercedes · Red Bull · Williams · Alpine · **Graphite** · **Indigo**; default **McLaren** | 11 **F1-team liveries** (Alpine, Aston Martin, Audi, Cadillac, Ferrari, Haas, McLaren, Mercedes, Racing Bulls, Red Bull, Williams); default **Aston Martin**; **no Graphite/Indigo** | Palette set + default changed. Confirm the final list and default. |
| **Day display default** | Appearance: **default Actual** | default **Relative** | Confirm default. |
| **Sunrise/sunset default** | Appearance: **default on** | default **off** | Confirm default. |
| **Theme default** | "real app follows macOS" (Auto) | default **Light** | Confirm whether default should be Auto. |
| **Cities drag-to-reorder** | City rows have a **drag handle** to reorder | Drag-reorder is **inert**; ordering is via the **Sort** control only | Confirm: drop the handle from the design, or implement drag. |
| **Popover drop shadow** | Popover §1: "large soft drop shadow" | Reduced to a smaller, window-like shadow (radius 35→18, y-offset 28→8) | UAT: the large shadow read heavy next to standard macOS windows (Settings / Finder). Confirm the lighter shadow, or update the spec. |
| **Popover top notch** | Popover §1: "small notch at top pointing to the menu-bar item" | **Removed** | Read as a stray artifact (especially while floating, detached from the bar) with no clear purpose. Confirm removal, or restyle if it should stay. |

---

*Maintainers: when you add a feature that isn't in the handoff, or knowingly ship something different from the prototype, add a row here so the design partner can keep the HTML as the single source of truth.*
