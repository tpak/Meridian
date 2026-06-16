# Design sync — v4 menu-bar "Stacked" layout (issue #142)

**Status:** implemented as an opt-in interim restore on `feature/stacked-menubar-preset`, in local
UAT (`4.0.0-beta23`). Default **off** — every existing user keeps the single-line item.
**Purpose of this doc:** the v4 handoff (`README.md` §G) specified the menu-bar item as **single-line
only** (five density presets). Issue #142 asks for the pre-v4 **two-line "stacked"** item back
(city name *over* the time) because it's **narrower per city**, so more favourites fit in a narrow /
notched menu bar before macOS clips them. This note documents what shipped in the beta so the design
partner can fold a proper stacked layout into the prototypes and return font/spacing/dot direction.
Hand this back with the screenshots from the UAT build.

---

## Why it's back

- A single-line `● IST 7:47 AM` item is **wide**. With 3–4 favourites on a 13" MacBook with a notch,
  the rightmost cities get clipped by the notch / Control Center.
- The classic two-line item stacks **name over time**, roughly **halving the width per city** at the
  cost of height (which the menu bar already reserves anyway). This is the space win #142 is after.
- This is the layout that existed pre-v4. The rendering code was never deleted — it lived behind a
  compile-time flag. This change makes it a **runtime, user-selectable** option; it does **not**
  change anything for users who stay on single-line.

## What shipped in the beta (interim engineering restore)

This is the *legacy* two-line item, unmodified — deliberately minimal so the design partner defines
the real v4 look. It is **not** yet styled to the Daybreak language.

- **Where:** Settings → Menu Bar → Preset grid. A **6th card, "Stacked"**, sits after "Mono · no
  dots". Selecting it switches the menu-bar item to two lines; selecting any of the 5 single-line
  presets switches back.
- **Layout rendered:**

  ```
  Single-line (today's default)        Stacked (the 6th preset)
  ┌────────────────────────┐           ┌──────────┐┌──────────┐
  │ ● IST 7:47 AM  ● DEN…  │           │   IST    ││   DEN    │
  └────────────────────────┘           │ 7:47 AM  ││ 8:17 PM  │
                                        └──────────┘└──────────┘
  ```
  Top line = city name (`compactMenuTitle`), bottom line = time, with optional day/date
  (`compactMenuSubtitle`). The existing fine-tune toggles (place / day / date / 24h) still apply and
  decide what lands on each line.
- **Color dots:** **dropped in stacked mode** (the legacy two-line renderer never drew one). The
  "Stacked" preset sets Color dots off, and the Settings live-preview omits the dot in this mode so
  preview == reality. **This is the biggest open design question** — see below.
- **Live preview strip** at the top of the pane renders a two-line chip when Stacked is active, so
  the user sees the shape before committing. Rough sizing; not final type.

## 🎨 Open design questions (please decide & return)

1. **Dots in stacked mode — yes/no, and where?** Today: no dot. If yes, likely a small dot leading
   the **name** line. This needs a real spec (size, baseline, spacing) — it's net-new vs. the legacy
   renderer.
2. **Type & metrics.** The legacy item uses bold system 10pt for the name line and monospaced-digit
   10pt for the time line, with a compressed line-height to fit two lines in the ~24pt bar. Confirm
   the v4 type ramp / weights / line-height you want here.
3. **Settings presentation.** Shipped as a **6th preset card** (per the decision on this issue). Note
   it conflates *layout* with *density* — the 5 single-line presets are density variants, "Stacked"
   is a layout switch. If you'd prefer an **orthogonal "Layout: Single-line / Stacked" control** that
   composes with the density toggles, that's an easy pivot — flag it.
4. **Preview chip.** Final styling for the two-line chip in the Settings live-preview strip.
5. **Naming.** "Stacked" vs "Two-line" vs other. (Avoid "Compact" — in v4 that's already the name of a
   single-line density preset; pre-v4 "compact" *was* this stacked mode, so the word is overloaded.)
6. **Truncation / max width** behavior with long city labels in two-line mode.

## Needs-design-pass checklist

- [ ] Dot decision for stacked mode (Q1) + spec if kept
- [~] Fonts / line-height (Q2): now natural line height (no compression) + 50/50 split, matching the
      Settings preview and the design's tabular-figure treatment. Name = SF semibold 10, time = SF
      regular tabular 10. Open: the design mockup specifies weight **550** + `letter-spacing -0.01em`
      for the single-line item — confirm whether the stacked lines should adopt 550 vs the current
      semibold.
- [ ] Confirm 6th-preset-card vs orthogonal layout toggle (Q3)
- [ ] Preview-strip two-line chip styling (Q4)
- [ ] Final option name (Q5)
- [ ] Update `Meridian - Settings.dc.html` prototype to include the stacked option + preview
- [ ] Update `README.md` §G to describe the menu-bar item's two layout modes

## Implementation notes (for the engineer picking this up after the design pass)

- Runtime switch: `kMenubarV4SingleLine` in `Preferences/Menu Bar/StatusItemView.swift` is now a
  computed `var` = `!menubarStackedLayoutEnabled`, backed by UserDefault
  `com.tpak.meridian.v4.menubarStacked` (default false). The two-line render path
  (`StatusItemView` constraints + `applyContent`, `StatusContainerView` width math,
  `TimezoneDataOperations.compactMenuTitle/Subtitle`) was already present and is unchanged.
- The Settings toggle writes the key via `@AppStorage`; `StatusItemHandler` rebuilds the menu-bar
  container on any `UserDefaults.didChangeNotification`, so the layout swaps live.
- Consistent with the sibling v4 keys (`menubarColorDots`, `menubarPreset`), the new key is **not**
  registered in `AppDefaults.defaultsDictionary()` and **not** in `SettingsManager` export/import.
  If we want any of the v4 menu-bar keys to round-trip in settings export, do them together as a
  separate cleanup.
