# Meridian v4 Redesign — Autonomous Build Log

> **Historical — completed.** v4 shipped GA as 4.0.0 on 2026-06-20. The `useDaybreakPanel` and
> `useV4Settings` rollback flags — and the legacy AppKit panel / storyboard Preferences stack they
> gated — were deleted in #166, so the fallback instructions below no longer apply.
> (`kMenubarV4SingleLine` survives, but as a user preference: the Settings → Menu Bar "Stacked"
> preset, issue #142.) Kept as a record of how the redesign was built. For the current architecture
> see `CLAUDE.md`.

This document tracks the v4 visual redesign (the "Daybreak" refresh). It is maintained by
Claude Code during the autonomous build so the state of the work is legible at a glance.

- **Spec (canonical):** `design_handoff_meridian_v4/` — HTML prototypes are the source of truth
  for look + behavior. README.md in that folder explains the dynamic rules (§A–G).
- **Branch / worktree:** `feature/v4-redesign` checked out at `/Users/chris/source/Meridian-v4`.
  `main` and `/Users/chris/source/Meridian` are intentionally untouched.
- **Target release:** 4.0.0 (design footer reads "Meridian 4.0"). UAT betas: `4.0.0-betaN`.

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Panel presentation | Restyled detached `NSPanel` (not `NSPopover`) | Preserves float-on-top + cmd-Q/W/,/C key handling already in `CustomPanel` |
| Isolation | Dedicated git worktree | Many agents editing for hours; main checkout can't be collateral damage |
| Build strategy | Build new SwiftUI views alongside old AppKit; swap entry points when proven | App stays runnable/compilable throughout |
| Model layer | Reuse `DataStore` / `TimezoneData` / `TimezoneDataOperations` / Solar | Time-travel = existing `sliderValue`; sunrise/sunset already computed |

## Phases

- [ ] **Phase 0 — Foundation:** design tokens (Swift), pure logic port (phase engine, offset,
      time parser, sky ramp) + unit tests, codebase API inventory.
- [x] **Phase 1 — Daybreak popover:** hero, city cards, scrubber, editable times. *(builds; 260 tests green; adversarial review done + fixes applied; **4.0.0-beta1 installed & running** at ~/Applications/Meridian-beta.app for UAT)* → UAT beta 1 ✅
- [x] **Phase 3 — Settings window:** NavigationSplitView shell + 5 panes (Cities/Menu Bar/Appearance/Time Travel/General), wired to Daybreak footer + ⌘, behind `useV4Settings`. *(builds; 260 tests green; adversarial review in progress)* → folds into UAT beta 2
- [x] **Phase 2 — Menu-bar density presets:** single-line "● NAME TIME" + per-city color dots, flag-gated `kMenubarV4SingleLine`; width measured directly so it can't clip. *(builds; 260 tests green)* → folds into UAT beta 3
- [~] **Phase 4 — Integration, regression, localization, polish, final beta.**

## Flags (all default to the v4 path on this branch; flip for instant fallback)
- `AppDelegate.useDaybreakPanel` — v4 popover vs legacy `PanelController`.
- `AppDelegate.useV4Settings` — v4 Settings window vs legacy storyboard Preferences.
- `kMenubarV4SingleLine` (StatusItemView.swift) — v4 single-line menu-bar item vs legacy two-line.
- [ ] **Phase 2 — Menu-bar density presets.** → UAT beta 2
- [ ] **Phase 3 — Settings window** (5 panes). → UAT beta 3
- [ ] **Phase 4 — Integration, regression, localization, polish.** → UAT beta 4 → GA 4.0.0

## UAT guide (read this first when you're back)

**Installed & running:** `4.0.0-beta4` at `~/Applications/Meridian-beta.app` (shares your real
timezones/prefs via `com.tpak.Meridian`). Your production `/Applications/Meridian.app` was quit so only
the beta runs. CI gates all green locally: build ✅, 260 unit tests ✅, SwiftLint 0 serious ✅,
entitlements unchanged ✅. Four adversarial review rounds (engine/views → settings → final
security+integration); all HIGH/MEDIUM findings fixed.

**What to UAT (all three surfaces are live):**
1. **Daybreak popover** — click the menu-bar item. Check: hero sky color matches time of day; city
   cards show sun/moon + offset relative to your current location; drag the scrubber (snaps 15 min) and
   watch times/day-tags recompute; double-click any time to edit it; ‹ › nudge; ↺ Back to now.
2. **Settings** — footer "Settings" / ⌘, / dock menu. Five panes: Cities (add/star/color/label/reorder/
   home), Menu Bar (5 presets + fine-tune + dots), Appearance (theme, F1 livery accents + disclaimer,
   day display, text size), Time Travel (forward/back days, snap), General (login/updates/beta/debug/
   export/import).
3. **Menu bar** — favourites now render single-line "● NAME TIME" with per-city color dots.

**Instant fallback if anything's wrong** (flip a flag, rebuild a beta):
- `AppDelegate.useDaybreakPanel = false` → legacy popover.
- `AppDelegate.useV4Settings = false` → legacy storyboard Preferences.
- `kMenubarV4SingleLine = false` (StatusItemView.swift) → legacy two-line menu bar.

**Switch back to production:** `osascript -e 'tell application "Meridian" to quit'` then
`open /Applications/Meridian.app` (or `rm -rf ~/Applications/Meridian-beta.app` first).

**Known follow-ups (not blockers; deferred for GA):**
- **Localization** — new SwiftUI strings are English literals; need `String(localized:)` + `.xcstrings`
  entries before GA to keep the 15-language coverage.
- **Geocoded city search** — Settings → Cities "add" currently searches IANA timezone identifiers
  locally; wiring the existing CLGeocoder path for "Denver, CO"-style city search is a follow-up.
- **Visual fine-tuning** — popover notch offset, menu-bar dot baseline, and exact paddings couldn't be
  eyeballed headlessly; expect small tweaks after your visual pass.
- **"Day display" pref → Daybreak** — the Appearance "Day display" segment (Relative/Actual/Date/Hide)
  isn't yet read by the popover, which uses its own day-tag scheme (`+2d`/`tmrw`). Needs a design
  decision on how the four modes map to the v4 row sub-label before wiring (or hide the control in v4).
  *(Sunrise/sunset toggle, Text size, and Show Time Scroller are now wired.)*

**Ship path:** UAT → sign off → either cut a Sparkle `4.0.0-betaN` to widen testing, or `make release
VERSION=4.0.0` for GA (after localization). The redesign lives only on `feature/v4-redesign`; `main` is
untouched.

## Build log

- Worktree + branch created from `main` @ d076bc22.
- Design handoff committed as canonical spec.
- Tooling: `scripts/xcodeproj_add.rb` (idempotent file→pbxproj registration; project is objectVersion 54, no synchronized groups, so new files must be registered).
- Recon: 8 subsystem API cheatsheets under `design_handoff_meridian_v4/recon/`.
- **Phase 0 foundation (GREEN):**
  - `DaybreakEngine.swift` — pure port of design logic (phase, sun events, offsets, time parser, sky ramp, scrubber math). 33 unit tests pass.
  - `DaybreakTokens.swift` — SwiftUI design tokens (surfaces, hero sky, sun/moon discs, row tints, gold accent).
  - `DaybreakComputation.swift` — Foundation/Solar → integer primitives (local minutes, day ordinal, sunrise/sunset window; scrub-aware cache).
  - `DaybreakDefaults.swift` — additive v4 prefs (home tz, travel back-days, snap step).
  - `DaybreakViewModel.swift` — assembles hero + city rows + scrubber snapshot; 1s tick + change observation.
  - App target builds; reuses existing `TeamAccent`/`Theme`/`TimeFormat`/`DataStore` rather than reinventing.
- **Phase 1 (Daybreak):** SwiftUI popover hosted in a fresh `DaybreakPanel`; adversarial review fixed 3 HIGH bugs (DST marker drift, Solar cache collision, commit-on-blur). → `4.0.0-beta1`.
- **Phase 3 (Settings):** 5 SwiftUI panes (parallel agents) over a locked backbone; adversarial review fixed a drag-reorder corruption + a Sparkle auto-update desync + home-picker consistency. → folded into `4.0.0-beta2`.
- **Phase 2 (menu bar):** flag-gated single-line item + per-city dots; width measured from the real string. → folded into `4.0.0-beta3`.
- **Phase 4 (verify):** full build + 260 tests + SwiftLint 0-serious + entitlements-unchanged; final security/integration review run. UAT guide above.
- Reviews were run as parallel multi-agent workflows (recon → engine/views → settings → final), each adversarially verifying findings before fixes were applied.
