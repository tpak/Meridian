# /release — Ship a new Meridian version

Usage: `/release VERSION` (e.g. `/release 2.16.0`)

## Pre-flight checks

1. Confirm you are on `main` and it is up to date: `git checkout main && git pull`
2. Verify no open PRs that should be included: `gh pr list --state open`
3. Verify CI is green on main: `gh run list --branch main --limit 1`
4. Check the current version: `gh release view --json tagName -q .tagName`

## Build release notes

1. Collect PRs merged since the last release tag: `gh pr list --state merged --search "merged:>LAST_RELEASE_DATE" --limit 20`
2. Write notes following the style in CLAUDE.md: short, user-facing, one line per change, no internal details. Reference closing GitHub issues inline (e.g. "Add keyboard shortcuts (#50)")
3. For multiline notes, call the release script directly instead of `make release` to avoid shell interpolation issues:
   ```bash
   bash scripts/release.sh -n "LINE1
   LINE2" VERSION
   ```

## Execute the release

1. Run: `bash scripts/release.sh -n "NOTES" VERSION`
2. The script handles everything: version bump, build, sign, notarize, GitHub release, appcast, Homebrew cask

## Post-release verification

1. Verify CI passes on the version bump and appcast commits: `gh run list --branch main --limit 3`
2. If any CI run fails, investigate immediately — do NOT ignore failures
3. Verify the GitHub release exists: `gh release view vVERSION`
4. Confirm the release notes are user-facing and concise; edit with `gh release edit` if needed
