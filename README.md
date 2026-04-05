<p align="center">
  <img src="icon.png" width="128" height="128" alt="Meridian">
</p>

<h1 align="center">Meridian</h1>

<p align="center">
  <a href="https://github.com/tpak/Meridian/actions/workflows/ci.yml"><img src="https://github.com/tpak/Meridian/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/tpak/Meridian/actions/workflows/codeql.yml"><img src="https://github.com/tpak/Meridian/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/tpak/Meridian/blob/main/.swiftlint.yml"><img src="https://img.shields.io/badge/SwiftLint-configured-brightgreen" alt="SwiftLint"></a>
  <a href="https://github.com/tpak/Meridian/blob/main/LICENSE"><img src="https://img.shields.io/github/license/tpak/Meridian" alt="License"></a>
</p>

A macOS menu bar world clock. Track time across zones for your team, friends, and family.

## Features

- **Menu bar native** — lives in your macOS menu bar, one click away
- **Multiple time zones** — add as many locations as you need
- **3 display modes** — icon only, standard text, or compact view
- **Time scrubbing** — slide to see what time it will be elsewhere
- **Sunrise/sunset** — know when the sun rises and sets in each zone
- **Pin to desktop** — float the panel above all windows and drag it anywhere
- **Keyboard shortcuts** — ⌘Q, ⌘W, ⌘,, ⌘C in the panel, plus a configurable global hotkey
- **Start at login** — launches automatically with your Mac
- **Ad-free & open source**

## Install

### Homebrew (recommended)

```bash
brew tap tpak/tpak
brew install --cask meridian
```

Updates are delivered automatically via Sparkle and also via `brew upgrade meridian`.

### Direct download

Download the latest `.zip` from [GitHub Releases](https://github.com/tpak/Meridian/releases), unzip, and drag Meridian to your Applications folder.

Requires macOS 13 (Ventura) or later.

## Development

Requires Xcode 15+ and macOS 13 (Ventura) or later.

```bash
git clone https://github.com/tpak/Meridian.git
cd Meridian
```

### Build & Run

```bash
make build        # Release build
make debug        # Debug build
make install      # Build + copy to /Applications
make clean        # Remove build artifacts
```

### Test & Lint

```bash
make test         # Run all unit tests
make lint         # Run SwiftLint
```

### Bump Version

Version is set via `MARKETING_VERSION` in the Xcode project (3 build configurations). To bump:

1. Search for `MARKETING_VERSION` in `Meridian/Meridian.xcodeproj/project.pbxproj`
2. Update all 3 occurrences to the new version
3. Commit, tag, and create a [GitHub Release](https://github.com/tpak/Meridian/releases)

### Project Structure

User-facing names — product, bundle, scheme — are all "Meridian".

```
Meridian/
├── Meridian.xcodeproj      # Xcode project (scheme: Meridian)
├── App/                    # Localization, Info.plist, entitlements
│   ├── Overall App/        # AppDelegate, DataStore, extensions
│   ├── Panel/              # Menu bar panel UI + data layer
│   ├── Preferences/        # Settings (General, Appearance, About)
│   └── Dependencies/       # Vendored: DateTools, Solar
├── CoreLoggerKit/          # SPM package — OSLog wrapper
├── CoreModelKit/           # SPM package — TimezoneData model
├── MeridianUnitTests/      # Unit tests
└── MeridianUITests/        # UI tests
```

## Localization

Meridian is available in 15 languages. Translations use Apple's [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) (`.xcstrings`).

| Language | Status |
|----------|--------|
| Croatian, German, Spanish | Excellent |
| Chinese (Simplified/Traditional), Russian, Turkish, Polish, Portuguese (Brazil) | Good |
| Korean, Japanese, French, Ukrainian, Arabic, Hindi | Partial |

### Contributing Translations

1. Open `Meridian/App/Localizable.xcstrings` in Xcode's String Catalog editor
2. Add or improve translations for your language
3. Submit a pull request

### Translation Credits

Translations were originally contributed to the [Clocker](https://github.com/n0shake/Clocker) project and restored for Meridian:

- **[Abhishek Banthia](https://github.com/n0shake)** — all base translations across 15+ languages
- **[Ping](https://github.com/milotype)** — Croatian translation updates
- Community translators via [Crowdin](https://crowdin.com/project/clocker)

## Troubleshooting

### Debug Logging

Meridian logs key lifecycle events (launch, quit, sleep/wake) to macOS unified logging by default. To enable verbose debug logging for all user actions and state changes:

1. Open **Settings** (⌘,) → **About** tab
2. Check **Enable Debug Logging**

View logs in Console.app (filter by process "Meridian") or from the terminal:

```bash
# All Meridian logs from the last 24 hours
log show --predicate 'subsystem == "com.tpak.Meridian"' --last 24h

# Lifecycle events only (always on)
log show --predicate 'subsystem == "com.tpak.Meridian" AND category == "lifecycle"' --last 7d

# Debug events only (when toggle is enabled)
log show --predicate 'subsystem == "com.tpak.Meridian" AND category == "debug"' --last 1h
```

To export logs as a text file: enable debug logging, then click **Export Log** in the About tab.

### Crash Detection

If Meridian exits unexpectedly (crash, force quit, or system restart), the next launch will log "Previous session exited uncleanly" to the lifecycle category. Check Console.app or `log show` to see this.

## Contributing

Pull requests welcome. Please open an issue first to discuss larger changes.

## Origin

Meridian began as a fork of [Clocker](https://github.com/n0shake/Clocker) by [Abhishek Banthia](https://github.com/n0shake). Since forking, it has diverged significantly — Firebase removal, async/await migration, feature simplification, full rebrand to 100% Swift — and is now maintained independently.

Thank you to Abhishek for creating the original Clocker and releasing it under the MIT License.

## License

MIT License. See [LICENSE](LICENSE) for the full text.
