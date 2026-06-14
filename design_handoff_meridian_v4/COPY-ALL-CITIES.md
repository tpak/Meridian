# Design sync — v4 popover footer (copy + float)

**Status:** implemented in the v4 build (`feature/v4-redesign`), pending UAT.
**Purpose of this doc:** keep the design prototypes (`Meridian - Daybreak.dc.html`) in sync with two
footer behaviors carried over from v3 that the original handoff didn't cover. Hand this back to the
design partner so the popover mockups match. This doc covers:

1. **Copy all city times** — restored footer copy control (below).
2. **Float control (was "Pin") + draggable floating popover** — see the section at the end.

---

## What it is

v3 had a small copy icon in the popover footer. Clicking it put **every tracked city's current time**
on the clipboard as text, so the user could paste a quick "here's what time it is everywhere" list
into a message, calendar invite, email, etc.

v4's first cut dropped it. This restores it, drawn in the Daybreak style.

### v3 reference (the thing we're restoring)
Footer, bottom-left: `[⚙ gear]  [⧉ copy]  ……  v3.1.2  ……  [📌 pin]`.
The copy icon sat immediately to the right of the gear.

---

## v4 placement & appearance

The Daybreak footer today is:

```
┌──────────────────────────────────────────────────────────────┐
│  Settings   ⧉            v4.0.0            Float ▲             │
└──────────────────────────────────────────────────────────────┘
   └ text btn └ NEW copy   └ version (center)   └ float text btn
```

(The right-hand button reads `Float ▲` / `Unfloat ▼` depending on state — see the float section.)

- **Position:** in the left group, immediately right of the **Settings** text button — mirrors v3's
  "gear + copy together on the left."
- **Icon:** SF Symbol `doc.on.doc`, 12pt, weight medium. Icon-only (no text label), to sit cleanly
  next to the text buttons without crowding the centered version string.
- **Color:** `palette.foot` (same as the Settings / Float buttons — adapts light/dark).
- **Tap feedback:** the icon flips to a `checkmark` for ~1.4s, tinted with the Daybreak **accent gold**
  (`palette.accent`), then reverts. No toast, no modal — minimal, in keeping with the v4 footer.
- **Tooltip / a11y label:** "Copy all city times".

> Design partner: please add this icon to the footer in the prototype, with the checkmark confirmation
> state. If you'd prefer a different affordance than the icon→checkmark flip (e.g. a brief "Copied"
> pill/toast above the footer), flag it — see open questions.

---

## Behavior

- Copies the **hero (current location) first**, then **each city card**, top-to-bottom — i.e. exactly
  the order shown in the popover. The hero is never duplicated in the card list.
- Reflects the **time scrubber**: if the user has traveled the slider into the future/past, the copied
  times are the *displayed* (traveled) times, not wall-clock now. (Matches v3, which copied the
  slider-adjusted time.)
- Honors the user's **12h/24h** setting (the `period` field is empty in 24h mode, so no stray "AM/PM").

### Text format (one city per line)

```
{City name} — {time}{ period}
```

Example (12-hour, "now"):

```
Melbourne — 10:47 PM
Djibouti — 3:47 PM
Paris — 2:47 PM
Denver — 6:47 AM
San Francisco — 5:47 AM
```

Notes:
- Separator between name and time is an em dash with spaces: ` — `.
- Lines are joined with `\n` (newline). This is a change from v3, which joined everything onto **one
  line** with ` / `. The multi-line list is more readable when pasted; calling it out so the design
  partner can weigh in.

---

## Open questions for design

1. **Richness of each line.** Right now it's just `Name — Time`. Should it also include the UTC
   offset and/or the relative day (e.g. `Denver — 6:47 AM (−16h · yesterday)`) so cross-day times
   aren't ambiguous when pasted? The data is available; it's a readability-vs-noise call.
2. **Confirmation affordance.** Icon→checkmark flip (current) vs. a small "Copied" toast/pill. v3 used
   a toast ("Copied to Clipboard"); v4 leans quieter. Preference?
3. **Header line?** Should the pasted block start with something like `Meridian · times as of <date>`
   for context, or stay as a bare list?
4. **Localization.** The em dash, the tooltip "Copy all city times", and any future "Copied" string
   should go through the string catalog before GA (consistent with the v4 localization blocker).

---

## Where it lives in code (for reference, not design)

- Footer button + checkmark state: `Meridian/Panel/Daybreak/DaybreakRootView.swift` (`copyAllButton`).
- Clipboard text assembly: `Meridian/Panel/Daybreak/DaybreakPanelController.swift`
  (`copyAllCitiesToClipboard()` / `copyLine(name:time:period:)`).
- Row/hero data it reads: `DaybreakSnapshot.hero` + `DaybreakSnapshot.cities` in
  `Meridian/Panel/Daybreak/DaybreakViewModel.swift`.

---

# Float control (was "Pin") + draggable floating popover

A second v3 behavior the redesign dropped and we've now restored. Two parts: a **rename** and a
**drag** behavior.

## 1. Rename: "Pin" → "Float"

The footer's right-hand button used to read `Pin ▲` / `Unpin ▼`. "Pin" was misleading and didn't
match the rest of the app — Settings → Menu Bar already calls this **"Float on top."** The button now
reads:

- **`Float ▲`** when the popover is *not* floating (tap to start floating).
- **`Unfloat ▼`** when it *is* floating (tap to return to the normal menu-bar-anchored popover).

Same `palette.foot` text style as the Settings button. Tooltip: *"Float on top (drag to move)"* /
*"Stop floating on top."*

> Design partner: please update the footer label in the prototype from Pin/Unpin to Float/Unfloat. The
> ▲/▼ arrows are carried over from v3 (▲ = raise/keep on top, ▼ = drop back) — keep or drop them, your
> call; flag a preference.

## 2. Draggable floating popover

When floating is **on**, the popover behaves like a normal free-floating window:

- It stays open (doesn't dismiss when you click elsewhere or the app loses focus).
- It floats above other windows (`.floating` level, joins all Spaces).
- **The user can drag it anywhere on screen** by grabbing its background/chrome (the hero area, the
  padding/gaps around the city cards). Interactive surfaces — the time scrubber, footer buttons, city
  rows, the hero inline time-edit — keep working; only non-interactive background starts a drag.
- **It remembers where it's dragged.** Reopening from the menu bar brings it back to where the user
  parked it (persisted across launches, clamped onto the current screen so a disconnected display
  can't strand it off-screen). When floating is first turned on, it stays where it currently sits
  (under the menu-bar item) until dragged.

When floating is **off** (default), nothing changes from today: the popover is anchored under the
menu-bar item and dismisses on click-away. Turning floating off re-anchors it under the item.

This matches v3 exactly (v3's `PanelController` set `isMovableByWindowBackground = true` in float mode
and autosaved the floating frame); it was simply not carried into the v4 panel until now.

### Design implications
- No new chrome is required for dragging — there's **no title bar or drag handle**; the whole
  background is the drag surface (standard `isMovableByWindowBackground`). If the design wants a
  visible "grab" affordance (e.g. a subtle handle or a different cursor hint), that's a net-new ask —
  flag it.
- The notch/arrow that points at the menu-bar item still renders while floating even after the popover
  is dragged away from the bar. v3 had the same quirk. Open question: should the notch be **hidden
  when floating** (since it no longer points at anything)? See open questions.

### Where it lives in code (for reference, not design)
- Float mode + drag + position persistence: `Meridian/Panel/Daybreak/DaybreakPanelController.swift`
  (`applyWindowMode`, `togglePin`, `windowDidMove`, `saveFloatingTopLeft` /
  `restoredFloatingTopLeft`).
- Footer Float/Unfloat button: `Meridian/Panel/Daybreak/DaybreakRootView.swift` (footer).

### Open questions for design (float)
1. **Notch while floating.** Hide the menu-bar pointer notch once the popover is floating/dragged away,
   or leave it (v3 left it)?
2. **Float/Unfloat arrows.** Keep `▲`/`▼`, or drop them now that the verb changed?
3. **Grab affordance.** Any visible hint that a floating popover is draggable, or rely on discovery
   (v3 had none)?
