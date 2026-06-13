# Meridian v4 Redesign — Autonomous Build Log

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
- [ ] **Phase 1 — Daybreak popover:** hero, city cards, scrubber, editable times. → UAT beta 1
- [ ] **Phase 2 — Menu-bar density presets.** → UAT beta 2
- [ ] **Phase 3 — Settings window** (5 panes). → UAT beta 3
- [ ] **Phase 4 — Integration, regression, localization, polish.** → UAT beta 4 → GA 4.0.0

## Build log

- Worktree + branch created from `main` @ d076bc22.
- Design handoff committed as canonical spec.
