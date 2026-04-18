# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Identity

**Meridian** (formerly Clocker) — macOS menu bar world clock app. ~11K lines of Swift across 77 files. Bundle ID: `com.tpak.Meridian`. Forked from [Clocker](https://github.com/n0shake/Clocker) by Abhishek Banthia.

GitHub repository: [`tpak/Meridian`](https://github.com/tpak/Meridian) — always use this URL for issues, PRs, and releases. The old Clocker repo is upstream and unrelated.

## Installation

```bash
brew tap tpak/tpak
brew install --cask meridian
```

Cask definition lives in [`tpak/homebrew-tpak`](https://github.com/tpak/homebrew-tpak). Updated automatically by the release script.

## Git Workflow

**Always create a feature branch before making changes.** Never commit directly to `main`. Use descriptive branch names like `fix/sunrise-bug` or `feature/accessibility-labels`. Open a PR when the work is ready for review. This applies to all work — bug fixes, features, refactors, doc updates.

## Build & Test Commands

```bash
# Build (Debug)
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# Build + Static Analysis
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build analyze \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# All unit tests
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug test \
  -only-testing:MeridianUnitTests -parallel-testing-enabled NO -disable-concurrent-destination-testing \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# Single test
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug test \
  -only-testing:MeridianUnitTests/MeridianUnitTests/testTimeDifference -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# Lint
swiftlint

# Release (bumps version, builds, signs, creates GitHub release, updates appcast)
make release VERSION=X.Y.Z
# With inline notes (one bullet per line):
make release VERSION=X.Y.Z NOTES="Fix bug
Add feature"
```

**Critical**: Always use `-parallel-testing-enabled NO` for unit tests. Parallel runners crash with "exit code 0" on macOS 15 due to Launch Services failures.

## Release Workflow

After merging PRs to `main`:

```bash
git checkout main && git pull
make release VERSION=X.Y.Z
```

The release script (`scripts/release.sh`) handles everything:
1. Bumps version in `project.pbxproj` (skips if already set)
2. Builds with Developer ID Application certificate (team `3LWTY5PDSS`)
3. Strips xattrs and re-signs Sparkle framework components
4. Notarizes with Apple via `xcrun notarytool` (keychain profile: `meridian-notary`)
5. Staples notarization ticket, creates clean zip (no `._*` files)
6. Signs zip with Sparkle EdDSA key
7. Creates GitHub release with zip attached
8. Updates `appcast.xml` with new entry, commits, and pushes
9. Updates Homebrew cask in `tpak/homebrew-tpak` via GitHub API

**Release notes** are auto-collected from all PRs merged since the last release tag. Override with `NOTES="..."` or specify a single PR with `PR=35`. If no PRs found, opens `$EDITOR`.

**Release notes style**: Keep notes short and user-facing. One line per change describing what was fixed or added — not why or how. No internal details (class names, property names, root cause analysis). Write for customers, not developers. Reference closing GitHub issues inline with the relevant change (e.g. "Add keyboard shortcuts (#50)"). Good: "Fix sunrise/sunset not displaying for some timezones". Bad: "Sunrise/sunset was only displayed when selectionType == .city; now checks for coordinates instead".

**Post-release cleanup** (do this after every release):
```bash
git fetch --prune origin                              # prune stale remote refs
git branch --merged main | grep -v '^\*\|  main$'     # list local branches fully merged into main
# For each merged branch:
git branch -d <branch>                                # delete local
git push origin --delete <branch>                     # delete remote (if remote still has it)
```
Only delete branches whose PR shows MERGED in `gh pr list --state all`. Never force-delete (`-D`) unless the branch is confirmed merged — use `-d` so git refuses if commits would be lost.

**Prerequisites** (one-time setup, see `developer-id.md`):
- Developer ID Application certificate in keychain
- Notarization credentials stored: `xcrun notarytool store-credentials "meridian-notary"`
- Sparkle EdDSA key (generated on first use by `sign_update`)

## Coming Back After Months Away

If you haven't touched this project in a while, here's how to get back up to speed and ship an update.

### Prerequisites Check

```bash
# 1. Verify Developer ID certificate is installed
security find-identity -v -p codesigning | grep "Developer ID"
# Should show: "Developer ID Application: Christopher Tirpak (3LWTY5PDSS)"

# 2. Verify notarization credentials are stored
xcrun notarytool history --keychain-profile "meridian-notary"
# Should list previous submissions (not an error)

# 3. Verify Sparkle sign_update is available (build project in Xcode first if missing)
find ~/Library/Developer/Xcode/DerivedData/Meridian-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update

# 4. Verify gh CLI is authenticated
gh auth status
```

If the Developer ID certificate has expired, renew at [developer.apple.com](https://developer.apple.com) → Certificates. If notarization creds are missing, re-store them:
```bash
xcrun notarytool store-credentials "meridian-notary" \
  --apple-id "YOUR_APPLE_ID" --team-id "3LWTY5PDSS" --password "APP_SPECIFIC_PASSWORD"
```

### Shipping an Update

```bash
# 1. Create a feature branch, make changes, push, open PR
git checkout -b feature/my-change
# ... make changes ...
git push -u origin feature/my-change
gh pr create --title "My change"

# 2. Wait for CI (Build & Lint + Unit Tests), then merge
gh pr merge --merge

# 3. Release (does everything: version bump, build, sign, notarize, GitHub release, appcast)
git checkout main && git pull
make release VERSION=X.Y.Z
```

### How Sparkle Auto-Update Works

1. App checks `appcast.xml` at `SUFeedURL` (hosted on GitHub raw) on the interval set in About preferences
2. If a newer `<sparkle:version>` exists, Sparkle downloads the zip from the GitHub release URL
3. Sparkle verifies the EdDSA signature (`sparkle:edSignature`) matches the public key in Info.plist (`SUPublicEDKey`)
4. For sandboxed apps, Sparkle uses XPC services (`-spks`, `-spki`) via the Installer Launcher Service
5. The update replaces the app bundle and relaunches

### Troubleshooting

| Problem | Fix |
|---------|-----|
| `No 'Developer ID Application' certificate found` | Install/renew at developer.apple.com → Certificates, Identifiers & Profiles |
| `Notarization credentials not found` | Re-run `xcrun notarytool store-credentials "meridian-notary"` |
| `Sparkle sign_update not found` | Open project in Xcode, build once to resolve SPM packages |
| Notarization rejected (Invalid) | Check `xcrun notarytool log <submission-id> --keychain-profile "meridian-notary"` for details |
| Users get Gatekeeper warning | Ensure `xattr -rc` and `ditto --norsrc` are in the release script (prevents `._*` files) |
| Sparkle update fails silently | Check Console.app for Sparkle logs; verify `SUEnableInstallerLauncherService` is in Info.plist |

## Architecture

### Data Flow

`DataStore` (singleton) → `TimezoneData` (model, NSSecureCoding) → `TimezoneDataOperations` (computed display values)

- **DataStore** (`Overall App/DataStore.swift`) — central state hub, stores timezone list in UserDefaults. Protocol `DataStoring` enables test injection.
- **TimezoneData** (`CoreModelKit/Sources/CoreModelKit/TimezoneData.swift`) — core model persisted as Data blobs in UserDefaults. Holds timezone ID, coordinates, custom label, format overrides.
- **TimezoneDataOperations** (`Panel/Data Layer/TimezoneDataOperations.swift`) — takes a TimezoneData + slider offset, produces formatted time/date strings, sunrise/sunset via Solar.

### UI Layers

**Menu bar panel** (main UI):
- `PanelController` → `ParentPanelController` (base class, manages table + slider)
- `TimezoneDataSource` drives the NSTableView of `TimezoneCellView` rows
- Modern slider scrubs ±48h; extensions in `ParentPanelController+ModernSlider.swift`

**Preferences** (3 tabs: General, Appearance, About):
- `PreferencesViewController` manages timezone list add/remove/reorder
- `TimezoneAdditionHandler` and `TimezoneSearchService` handle search (`@MainActor`, async/await)
- `AppearanceViewController` — time format, menubar mode, display options
- `AboutView` (SwiftUI) — version info and links

### Network & Geocoding

- `NetworkManager` — async/await HTTP client + `CLGeocoder` wrapper for address geocoding
- `TimezoneSearchService` — searches `TimeZone.knownTimeZoneIdentifiers` locally + geocodes via CLGeocoder
- No external API keys or third-party services required

### Localization

Uses Apple String Catalogs (`.xcstrings`) — 15 languages. All strings in `App/Localizable.xcstrings`.
Code uses `NSLocalizedString(key, comment:)` and the `.localized()` extension on `String` (`Overall App/String + Additions.swift`).
New SwiftUI strings should use `String(localized:)`.

### Start at Login

`StartupManager` uses `SMAppService.mainApp` (macOS 13+). No helper app needed.

### SPM Packages (local, under `Meridian/`)

- **CoreLoggerKit** — OSLog wrapper
- **CoreModelKit** — TimezoneData model (depends on CoreLoggerKit)

### Vendored Dependencies (no package managers)

- **DateTools** (Swift) — date formatting utilities
- **Solar** (Swift) — sunrise/sunset calculations

All in `Meridian/Dependencies/`.

## Key Files

| File | Role |
|------|------|
| `Panel/ParentPanelController.swift` | Main panel — largest UI file |
| `Preferences/General/PreferencesViewController.swift` | Timezone management |
| `Overall App/DataStore.swift` | Singleton state hub |
| `Preferences/Menu Bar/StatusItemHandler.swift` | NSStatusBar item + menubar timer |
| `Panel/Data Layer/TimezoneDataOperations.swift` | Time/date formatting + sunrise/sunset |
| `Preferences/General/TimezoneAdditionHandler.swift` | Search + add timezone logic |
| `AppDelegate.swift` | App entry point (`@main`), global shortcut, startup |

## Test Notes

- Unit tests in `Meridian/MeridianUnitTests/` (112 tests)
- `MockDataStore` available for DI; `MockURLProtocol` for network mocking
- UI tests in `Meridian/MeridianUITests/` (panel interactions)
- `@testable import Meridian` (module follows PRODUCT_NAME)

## SwiftLint Rules

Config in `.swiftlint.yml`. Key limits: line length 160/200, type body 300/600, function body 50/100, `force_cast` and `force_try` are errors. `Meridian/Dependencies/` and test directories are excluded.

## Project Structure

Top-level project directory is `Meridian/`. Inside it, `App/` contains localization resources, Info.plist, and entitlements. All target names, product names, and user-facing names are "Meridian".

The Xcode project structure has `Package.resolved` inside `Meridian/Meridian.xcodeproj/project.xcworkspace/xcshareddata/`, not at the repo root. Always verify file paths within the Xcode project structure before making git or file changes.

## Release Checklist

Before any release, run a full pre-release check and **show the status of each item** before proceeding:
1. CI passes on the PR branch **and** on main after merge
2. All file changes (including Info.plist, storyboards) are committed
3. Release notes don't break shell interpolation (no unescaped special chars in multiline strings passed to `make release`; use `bash scripts/release.sh -n "..."` directly for multiline notes)
4. Sparkle appcast configuration is correct (`SUFeedURL`, `SUPublicEDKey` in Info.plist)
5. After `make release` completes, run `gh run list --branch main --limit 3` and verify the version bump and appcast commits pass CI

## Test-Driven Implementation

Before implementing any feature or fix, follow this workflow:

1. **Write a validation script** at `scripts/validate_feature.sh` that checks for the expected outcome. For example, if adding an export log feature:
   - Grep the codebase to confirm the new menu item exists in the storyboard
   - Verify the correct OSLog subsystem/category is used (not a different scope)
   - Confirm the save dialog dimensions are at least 400x300
   - Run `xcodebuild build` to verify compilation
   - Check that all new Logger references use the unified Logger instance
2. **Run the validation script** — it should FAIL since the feature doesn't exist yet. If it passes, the checks aren't testing the right thing.
3. **Implement the feature.**
4. **Run the validation script again.** If ANY check fails, fix the issue and re-run. Do not present the result until all checks pass.
5. **Show the final diff and the passing validation output.**

## Large Refactors — Parallel Agents

For large refactors, use parallel agents to divide the work by concern. Coordinate results and present a unified summary with any conflicts between agents' changes.

**Agent 1 — UI/Storyboard**: Reorganize storyboard layout. Verify all IBOutlet connections are intact by grepping for `@IBOutlet` and matching against storyboard identifiers.

**Agent 2 — Swift Logic**: Refactor the corresponding Swift view controllers. Run a build after changes to verify compilation.

**Agent 3 — Security Review**: Audit changes for common macOS security concerns — sandbox entitlements, hardened runtime flags, insecure file operations (world-readable temp files, symlink attacks), unvalidated user input passed to shell or `NSAppleScript`, credentials or secrets in UserDefaults or logs, and App Transport Security exceptions. Flag anything that weakens the app's security posture.

**Agent 4 — Integration Validation**: After Agents 1–3 complete, verify the full build succeeds, run all existing tests, check for SwiftLint violations, and confirm no regressions in startup time by reviewing any async/geocoding calls on the main thread.

Adapt the agent breakdown to the specific refactor — not every change needs all four agents. The key principle is: separate concerns, run in parallel where possible, validate as the final step.

## Code Quality

When migrating APIs or renaming symbols, grep the **entire codebase** for all remaining references to the old API/name **before making any edits**. Show the full list of every file with references and **wait for approval** before proceeding. Use `grep -rn "OldName" Meridian/ --include="*.swift"` to catch stragglers. A single missed reference will break the CI build.
