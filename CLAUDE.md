# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Identity

**Meridian** (formerly Clocker) — macOS menu bar world clock app. ~9.9K lines of Swift across 60 source files (~14K including tests). Bundle ID: `com.tpak.Meridian`. Forked from [Clocker](https://github.com/n0shake/Clocker) by Abhishek Banthia.

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
# 1. Switch the user back to the released prod app and remove any local UAT beta
#    so they aren't accidentally testing an older or differently-signed build.
osascript -e 'tell application "Meridian" to quit' ; sleep 2
rm -rf ~/Applications/Meridian-beta.app
# Confirm /Applications/Meridian.app is the version we just released
# (Sparkle should have updated it after the appcast push; if not, apply the update)
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Meridian.app/Contents/Info.plist
open /Applications/Meridian.app

# 2. Prune merged branches
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

## Local Beta Builds for UAT

Before cutting a real release, build a clearly-labelled beta and run it side-by-side with the production app on the user's machine. Iterate `beta1` → `beta2` → ... on the same feature branch until the user signs off, then merge the PR and run `make release`.

### Why this exists
Production releases go through Sparkle to every user immediately. The user wants to UAT changes locally before that happens. This workflow keeps `/Applications/Meridian.app` (production) untouched while a `~/Applications/Meridian-beta.app` runs the in-progress build.

### How to build a beta

From the feature branch (do **not** merge to main yet):

```bash
# 1. Quit any running Meridian (production or previous beta)
osascript -e 'tell application "Meridian" to quit'
sleep 2

# 2. Build with version overrides — DO NOT edit project.pbxproj.
#    Bump the betaN suffix and CURRENT_PROJECT_VERSION on each iteration.
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  MARKETING_VERSION=2.19.1-beta1 CURRENT_PROJECT_VERSION=2191001

# 3. Verify the version stamped into the built bundle
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$HOME/Library/Developer/Xcode/DerivedData/Meridian-*/Build/Products/Debug/Meridian.app/Contents/Info.plist"

# 4. Install to ~/Applications (separate from /Applications/Meridian.app)
rm -rf ~/Applications/Meridian-beta.app
cp -R "$HOME/Library/Developer/Xcode/DerivedData/Meridian-*/Build/Products/Debug/Meridian.app" \
  ~/Applications/Meridian-beta.app
xattr -cr ~/Applications/Meridian-beta.app   # strip quarantine
open ~/Applications/Meridian-beta.app

# 5. Confirm it's running
pgrep -lf "Meridian-beta.app/Contents/MacOS/Meridian"
```

### Conventions
- **Naming**: `MARKETING_VERSION=X.Y.Z-betaN` (e.g. `2.19.1-beta1`, `2.19.1-beta2`). The user-visible version string in the panel footer reads `vX.Y.Z-betaN` — that's the unambiguous "this is the test build" signal.
- **Build number**: `CURRENT_PROJECT_VERSION=XYZNNN` (e.g. `2191001` for `2.19.1-beta1`). Doesn't render in the UI; just keeps Sparkle's internal comparison consistent.
- **Bundle ID stays `com.tpak.Meridian`**: the beta shares UserDefaults with prod, so the user's real timezones and prefs come along for realistic UAT.
- **Don't sign or notarize**: `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`. The beta is for the user's own machine; Gatekeeper is satisfied by `xattr -cr`.
- **Don't bump `project.pbxproj`**: the override is build-time only. The pbxproj retains the most recent released version. This prevents accidentally committing a beta version number to `main`.
- **Sparkle won't auto-update the beta**: the production appcast tops out at the latest stable release; `2.19.1-beta1 > 2.19.1` lexically, so Sparkle sees nothing newer.

### Iteration cycle

When the user reports a problem with `betaN`:

```bash
# Make changes on the feature branch, commit, push (so the PR stays current)
git add ... && git commit -m "..." && git push

# Bump the beta number and rebuild + reinstall
osascript -e 'tell application "Meridian" to quit' ; sleep 2
xcodebuild ... MARKETING_VERSION=2.19.1-beta2 CURRENT_PROJECT_VERSION=2191002
rm -rf ~/Applications/Meridian-beta.app
cp -R "$HOME/Library/Developer/Xcode/DerivedData/Meridian-*/Build/Products/Debug/Meridian.app" \
  ~/Applications/Meridian-beta.app
xattr -cr ~/Applications/Meridian-beta.app
open ~/Applications/Meridian-beta.app
```

### Switching back to production

```bash
osascript -e 'tell application "Meridian" to quit'
open /Applications/Meridian.app                  # already-installed prod
# OR
brew reinstall meridian                          # clean reinstall of latest stable
```

### When to graduate to a real release

Only after the user explicitly signs off on the latest beta:
1. Verify CI is green on the PR
2. `gh pr merge <N> --merge`
3. `git checkout main && git pull`
4. `make release VERSION=X.Y.Z NOTES="..."` (multiline and special characters are fine; `bash scripts/release.sh -n "..." X.Y.Z` works too)

The released binary is what Sparkle ships to all users; the beta UAT path makes sure that binary's behavior was confirmed by the user first.

## Sparkle Beta Channel

Meridian has a single Sparkle feed (`appcast.xml`) with two channels: the **default** channel (every user) and the **`beta`** channel (opt-in). Users opt in via the *"Receive beta releases"* checkbox in the About tab. The opt-in is persisted under `UserDefaultKeys.betaUpdatesEnabled` and surfaced to Sparkle through `SPUUpdaterDelegate.allowedChannels(for:)` in `AppDelegate`.

Sparkle's rule: an updater **always** sees default-channel items and additionally sees items in any allowed channel. So a beta opt-in user automatically rolls forward into the GA release once it lands on the default channel — no extra plumbing required.

### Cutting a beta release

```bash
git checkout main && git pull
make release VERSION=2.20.0-beta1     # or beta2, beta3, …
```

The release script auto-detects the `-betaN` suffix and:
- Tags the GitHub release as **prerelease** (`gh release create --prerelease`)
- Adds `<sparkle:channel>beta</sparkle:channel>` to the new `appcast.xml` item
- **Skips** the Homebrew cask update (cask tracks stable only)

Stable users will not see the beta. Users who toggled *Receive beta releases* on will be offered it on their next Sparkle check (or immediately if they just flipped the toggle on — the toggle triggers `checkForUpdateInformation()`).

### Cutting the GA after beta UAT

```bash
make release VERSION=2.20.0
```

Same as any other stable release. Beta-channel users see the GA item (no channel tag = default channel = always allowed) and version-compare ranks `2.20.0 > 2.20.0-beta3`, so they upgrade off the beta automatically.

### Beta channel vs. local UAT betas

These are different mechanisms with different audiences:
- **Local UAT betas** (above) — built with `xcodebuild` overrides, installed to `~/Applications/Meridian-beta.app` on the developer's own machine. No distribution, no Sparkle. For pre-PR sanity checks.
- **Sparkle beta channel** (this section) — full release pipeline, signed/notarized, distributed via Sparkle to opt-in users. For broader pre-GA testing.

Use a local UAT beta to gain confidence in a feature, then cut a Sparkle beta to widen the test pool, then cut GA.

### Cutting a beta off an unmerged feature branch

When you want a signed/notarized beta build for UAT (or to push to beta-channel users) **without merging the feature branch to main yet** — useful when the feature isn't ready for permanent main but a wider test pool would help.

`scripts/release.sh` allows beta versions (`X.Y.Z-betaN`) from any branch; only stable releases require main. The flow:

```bash
# 1. On the feature branch with everything committed and CI green:
git checkout feature/your-branch
bash scripts/release.sh -n "release notes" 2.21.0-betaN
```

The script bumps `pbxproj`, builds, signs, notarizes, creates a GitHub prerelease, and writes the appcast entry — **all on the feature branch**. It also tries to push the appcast.

**Important: at this point Sparkle beta-channel users still don't see the build**, because their `SUFeedURL` reads `appcast.xml` from `main`, which the feature-branch appcast change hasn't reached. To put the beta on the channel:

```bash
# 2. Cherry-pick ONLY the appcast.xml commit (NOT the pbxproj version bump):
APPCAST_COMMIT=$(git log feature/your-branch --oneline | grep "appcast.*betaN" | awk '{print $1}')
git checkout main && git pull
git cherry-pick $APPCAST_COMMIT
git push origin main
```

Why only the appcast and not the pbxproj bump: cherry-picking the version bump to main would set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to a value whose code isn't on main yet (the feature is still on the branch). Anyone building from main locally would produce a binary labelled with a version that doesn't match its source. Leave main's pbxproj at its real state; only the appcast pointer needs to land so beta-channel users discover the GitHub release.

**When the feature later merges to main**, the merge brings in the version bump from the feature branch. If you want to ship that bump as a stable release, run `make release VERSION=X.Y.Z` from main as usual — `release.sh`'s "version already set, skipping commit" branch handles the case where the bump is already there.

**Stable releases must still run from main.** The branch check in `release.sh` enforces this for non-beta versions.

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

The whole UI is SwiftUI. The v4 "Daybreak" redesign shipped in 4.0.0; the legacy storyboard/AppKit panel and Preferences stack — and the `useDaybreakPanel` / `useV4Settings` rollback flags that gated it — were deleted in #166. `Meridian/App/MainMenu.xib` is the only remaining Interface Builder file.

**Daybreak popover** (`Panel/Daybreak/`, main UI):
- `DaybreakPanelController` owns the window: positioning, show/hide, float mode, ⌘, / ⌘C actions
- `DaybreakPanel` is the borderless `NSPanel`; it hosts `DaybreakRootView` (hero + city rows + scrubber + footer, plus the popover chrome and light/dark resolution)
- `DaybreakViewModel` reads `DataStore` + prefs on a 1-second tick and publishes one immutable `DaybreakSnapshot` per recompute; `DaybreakEngine` and `DaybreakComputation` hold the pure phase/sky/offset math (no UIKit/AppKit)
- `DaybreakTokens` — design tokens transcribed from the handoff; `SunMoonDisc`, `DaybreakHeroView`, `DaybreakCityRow`, `DaybreakScrubber` are the leaf views
- `DaybreakScrubber` time-travels ±N days (range configurable in Settings → Time Travel); `DaybreakDefaults` holds the v4-only preference keys and accessors
- `CityColorStore` maps each city to an accent hex, stored additively in UserDefaults so `TimezoneData` is untouched

**Settings window** (`Preferences/V4Settings/`, 5 panes):
- `SettingsWindowController` hosts `SettingsRootView` — a `NavigationSplitView` with Cities · Menu Bar · Appearance · Time Travel · General, tinted by the user's `TeamAccent` livery
- `CitiesPane` — tracked timezone list (add/star/color/label/reorder, Home and current location), backed by `CityListModel` and `CitySearchService`
- `MenuBarPane` — density presets + fine-tuning; `AppearancePane` — theme, accent, time/day format, sunrise·sunset, text size; `TimeTravelPane` — scrubber range and snap step; `GeneralPane` — login item, Sparkle updates + beta opt-in, debug logging, settings export/import, About block (URLs in `AboutUsConstants`)
- Panes bind straight to `@AppStorage`/`DataStore`; only Cities needs a stateful model

**Menu bar item** (`Preferences/Menu Bar/`):
- `StatusItemHandler` owns the `NSStatusItem` and its refresh timer; `StatusItemView` / `StatusContainerView` render each favourite as "● NAME TIME" with a per-city color dot

### Network & Geocoding

- `GeocodingService` — `GeocodingServicing` protocol over MapKit's `MKGeocodingRequest` / `MKReverseGeocodingRequest`, with a timeout wrapper; injectable for tests
- `NetworkManager` — async/await HTTP client plus `geocodeAddress(_:geocoder:)`, which defaults to `MapKitGeocodingService`
- `CitySearchService` — instant, ranked local search over `TimeZone.knownTimeZoneIdentifiers` plus a UTC entry and a common-city alias table
- No external API keys or third-party services required

### Localization

Uses Apple String Catalogs (`.xcstrings`) — 15 languages. All strings in `App/Localizable.xcstrings`.
Code uses `NSLocalizedString(key, comment:)` and the `.localized()` extension on `String` (`Overall App/String + Additions.swift`).
New SwiftUI strings should use `String(localized:)`.

### Start at Login

`StartupManager` uses `SMAppService.mainApp` (macOS 13+). No helper app needed.

### Preferences & Settings JSON

- `AppDefaults` registers default values and runs one-time, idempotent migrations on launch: the v1 bool-semantics migration (issue #97), the stuck-home-row fix, and a cleanup of legacy Clocker / previous-author (`com.abhishek.*`) defaults keys. New code should read/write through the typed accessors and enums it exposes — avoid raw `UserDefaults` reads/writes.
- `UserDefaults + KVOExtensions.swift` adds typed getters keyed off `UserDefaultKeys` (string constants live in `Strings.swift`).
- `SettingsManager` exports/imports a JSON document to `~/.meridian/meridian_settings.json` (or any chosen location, or the clipboard). Schema is **v2** with full **v1 back-compat** for older exports. `startAtLogin` is exported but applied via `StartupManager` on import so the system actually registers/unregisters the login item.

### SPM Packages (local, under `Meridian/`)

- **CoreLoggerKit** — OSLog wrapper
- **CoreModelKit** — TimezoneData model (depends on CoreLoggerKit)

### Vendored Dependencies (no package managers)

- **DateTools** (Swift) — trimmed to what Meridian calls: `timeAgo(since:)`, `earlierDate`/`laterDate`, `days(from:calendar:)`, `hours(from:)` and the localized-strings bundle. The other ~1,600 unused lines were removed in #198; recover from git history if needed.
- **Solar** (Swift) — sunrise/sunset calculations

All in `Meridian/Dependencies/`.

## Key Files

| File | Role |
|------|------|
| `Panel/Daybreak/DaybreakPanelController.swift` | Owns the popover window (positioning, show/hide, float mode) |
| `Panel/Daybreak/DaybreakRootView.swift` | SwiftUI root — hero, city rows, scrubber, footer, popover chrome |
| `Panel/Daybreak/DaybreakViewModel.swift` | Builds the `DaybreakSnapshot` the views render |
| `Panel/Daybreak/DaybreakEngine.swift` | Pure phase/sky/offset math (no AppKit) |
| `Panel/Daybreak/DaybreakDefaults.swift` | v4-only preference keys + typed accessors |
| `Panel/Data Layer/TimezoneDataOperations.swift` | Time/date formatting + sunrise/sunset |
| `Preferences/V4Settings/SettingsRootView.swift` | Settings `NavigationSplitView` shell (5 panes) |
| `Preferences/V4Settings/CitiesPane.swift` | Timezone list (add/star/color/label/reorder, Home) |
| `Preferences/V4Settings/CityListModel.swift` | Stateful model behind the Cities list |
| `Preferences/V4Settings/CitySearchService.swift` | Ranked local city/timezone search |
| `Preferences/V4Settings/GeneralPane.swift` | Login item, updates + beta opt-in, debug logging, export/import, About |
| `Preferences/Menu Bar/StatusItemHandler.swift` | NSStatusBar item + menubar timer |
| `Overall App/DataStore.swift` | Singleton state hub (protocol `DataStoring` for DI) |
| `Overall App/AppDefaults.swift` | Default registration + one-time migrations (bool-semantics, home-row, legacy-defaults cleanup) |
| `Overall App/SettingsManager.swift` | Settings export/import (JSON v2 with v1 back-compat) |
| `Overall App/Strings.swift` | `UserDefaultKeys` constants |
| `AppDelegate.swift` | App entry point (`@main`), global shortcut, startup, Sparkle channels |

## Test Notes

- Unit tests in `Meridian/MeridianUnitTests/` (263 tests)
- `MockDataStore` available for DI; `MockGeocodingService` for geocoding
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
3. Release notes read as user-facing changes (see *Release notes style* above). Quotes, backticks, `$(...)` and newlines in `NOTES=` are safe — the recipe passes them to `release.sh` as a literal argument (#196)
4. Sparkle appcast configuration is correct (`SUFeedURL`, `SUPublicEDKey` in Info.plist)
5. After `make release` completes, run `gh run list --branch main --limit 3` and verify the version bump and appcast commits pass CI
6. **User manual is current** — `docs/manual.md` reflects any new/changed setting, option, or feature in this release (see *User Documentation* below)

## User Documentation

The end-user manual lives at **`docs/manual.md`** (a single page) and is published to **GitHub Pages**. Themed release notes live at `docs/RELEASE_NOTES_<version>.md`.

**Keep the manual in sync with every real change — not only at release time.** Whenever *any* PR adds, removes, or changes a user-facing setting, option, button or link, panel/menu-bar behavior, or keyboard shortcut, update `docs/manual.md` in that *same* PR. Do not defer manual updates to "release time" — the manual should never lag `main`. Treat a stale manual as a release blocker (Release Checklist item 6). When you document a new screen, also add a matching `<!-- screenshot: screenshots/… -->` placeholder so the image can be captured before the manual is published. The UI to document is the SwiftUI Settings window (`Preferences/V4Settings/*`) and the Daybreak popover (`Panel/Daybreak/*`) — the only UI there is. The in-app **Settings → General → Open Manual** button links to this page (`AboutUsConstants.ManualURL`).

## Test-Driven Implementation

Before implementing any feature or fix, follow this workflow:

1. **Write a validation script** at `scripts/validate_feature.sh` that checks for the expected outcome. This path is **gitignored** — it's a scratch file each task rewrites from scratch, so it never lands in a commit and parallel branches can't conflict on it. Paste the passing output into the PR instead. For example, if adding an export log feature:
   - Grep the codebase to confirm the new menu item exists in the storyboard
   - Verify the correct OSLog subsystem/category is used (not a different scope)
   - Confirm the save dialog dimensions are at least 400x300
   - Run `xcodebuild build` to verify compilation
   - Check that all new Logger references use the unified Logger instance
2. **Run the validation script** — it should FAIL since the feature doesn't exist yet. If it passes, the checks aren't testing the right thing.
3. **Implement the feature.**
4. **Run the validation script again.** If ANY check fails, fix the issue and re-run. Do not present the result until all checks pass.
5. **Show the final diff and the passing validation output.**
6. **Promote anything durable.** If a check encodes an invariant worth keeping — not "did I build this feature" but "is this still true of the repo" — move it into its own named script under `scripts/` before the scratch file is overwritten. `scripts/check_localization.sh` (every localizable literal has a catalog entry) is the current example.

## Large Refactors — Parallel Agents

For large refactors, use parallel agents to divide the work by concern. Coordinate results and present a unified summary with any conflicts between agents' changes. Use the most sensible model for those agents to keep costs under control.

**Agent 1 — UI/Storyboard**: Reorganize storyboard layout. Verify all IBOutlet connections are intact by grepping for `@IBOutlet` and matching against storyboard identifiers.

**Agent 2 — Swift Logic**: Refactor the corresponding Swift view controllers. Run a build after changes to verify compilation.

**Agent 3 — Security Review**: Audit changes for common macOS security concerns — sandbox entitlements, hardened runtime flags, insecure file operations (world-readable temp files, symlink attacks), unvalidated user input passed to shell or `NSAppleScript`, credentials or secrets in UserDefaults or logs, and App Transport Security exceptions. Flag anything that weakens the app's security posture.

**Agent 4 — Integration Validation**: After Agents 1–3 complete, verify the full build succeeds, run all existing tests, check for SwiftLint violations, and confirm no regressions in startup time by reviewing any async/geocoding calls on the main thread.

Adapt the agent breakdown to the specific refactor — not every change needs all four agents. The key principle is: separate concerns, run in parallel where possible, validate as the final step.

## Code Quality

When migrating APIs or renaming symbols, grep the **entire codebase** for all remaining references to the old API/name **before making any edits**. Show the full list of every file with references and **wait for approval** before proceeding. Use `grep -rn "OldName" Meridian/ --include="*.swift"` to catch stragglers. A single missed reference will break the CI build.
