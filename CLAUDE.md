# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Identity

**Meridian** (formerly Clocker) — macOS menu bar world clock app. ~11K lines of Swift across 77 files. Bundle ID: `com.tpak.Meridian`. Forked from [Clocker](https://github.com/n0shake/Clocker) by Abhishek Banthia.

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

**Release notes** are auto-collected from all PRs merged since the last release tag. Override with `NOTES="..."` or specify a single PR with `PR=35`. If no PRs found, opens `$EDITOR`.

**Prerequisites** (one-time setup, see `developer-id.md`):
- Developer ID Application certificate in keychain
- Notarization credentials stored: `xcrun notarytool store-credentials "meridian-notary"`
- Sparkle EdDSA key (generated on first use by `sign_update`)

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

## Directory Structure Note

Top-level project directory is `Meridian/`. Inside it, `App/` contains localization resources, Info.plist, and entitlements. All target names, product names, and user-facing names are "Meridian".
