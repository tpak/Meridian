# TODO

## Dead code — medium/low confidence (revisit before next release)

From dead code audit 2026-04-18. High-confidence items already removed in `chore/remove-dead-code`.

### Medium confidence

- [ ] **`GlobalShortcutMonitor.swift:4`** — `import Carbon.HIToolbox` appears unused. File uses hard-coded numeric key codes instead of `kVK_*` constants. Verify nothing transitive relies on it, then remove.
- [ ] **`SearchDataSource.swift:40`** — `location` init parameter is effectively dead now that `SearchLocation` has only `.preferences`. Decide: drop the parameter and the `SearchLocation` enum entirely, or keep the seam for a future onboarding search surface.

### Low confidence (cascading)

- [ ] **`PanelTableView.swift:12`** — `enableHover` property is still read in `evaluateForHighlight()` but is only ever set to `true` in `awakeFromNib` (the setter that toggled it was removed). The `if enableHover == false` branches are now unreachable. Either wire hover disable back up or remove the property and dead branches.

### Date+TimeAgo commented block

- [ ] **`Meridian/Dependencies/Date Additions/Date+TimeAgo.swift:200-202`** — two lines of commented DateTools bundle code. Vendored third-party file; leave untouched unless we're intentionally modifying the vendored copy.
