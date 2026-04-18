# TODO

## Resume here next session (2026-04-18, paused for dinner)

Currently on branch `chore/remove-dead-code` with 2 commits ahead of `main`:
- `4fc808f` Remove high-confidence dead code
- `2816924` Remove medium-confidence dead code

All tests passing. Three tasks left to finish and ship v2.17.7:

### 1. Finish low-confidence cleanup in `PanelTableView.swift`

Decision already made: **just delete**, no product reason to keep a hover-disable path.

- Delete `private var enableHover: Bool = false` (line 12)
- Delete `enableHover = true` in `awakeFromNib()` (line 18)
- In `evaluateForHighlight()` (around line 80): delete the `if enableHover == false { return }` guard
- In `evaluateForHighlight(at:)` (around line 93): delete the `if enableHover == false { Logger.debug(...); return }` guard
- Drop the Date+TimeAgo TODO line below (vendored, leave-alone)
- If no items remain, delete `TODO.md` entirely in the same commit

Verify: `xcodebuild build analyze`, full unit tests with `-parallel-testing-enabled NO`, `swiftlint`. All must pass.

Commit: `Remove low-confidence dead code in PanelTableView and clear TODOs`

### 2. Open PR and merge

```
git push -u origin chore/remove-dead-code
gh pr create --title "Remove dead code" --body "<summary of the 3 commits: high/medium/low confidence dead code cleanup>"
# wait for CI green
gh pr merge --merge
```

### 3. Release v2.17.7

```
git checkout main && git pull
make release VERSION=2.17.7 NOTES="Internal cleanup: remove dead code. No user-facing changes."
gh run list --branch main --limit 3   # confirm post-release CI passes
```

### Date+TimeAgo commented block (keep as-is, noted for completeness)

- [ ] **`Meridian/Dependencies/Date Additions/Date+TimeAgo.swift:200-202`** — two lines of commented DateTools bundle code. Vendored third-party file; leave untouched unless we're intentionally modifying the vendored copy. (To be dropped from this file in task 1.)
