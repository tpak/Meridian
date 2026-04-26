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
- **Multiple time zones** — search by city, state, country, or timezone name
- **3 display modes** — icon only, standard text, or compact multi-zone view
- **Time scrubber** — slide forward or backward up to 6 days; `<` / `>` buttons step 15 minutes at a time
- **Direct time entry** — double-click any time to type a specific time and jump the scrubber there
- **Sunrise/sunset** — see when the sun rises and sets in each location
- **Favorites** — star a timezone to show it in the compact menubar display
- **Custom labels** — rename any timezone; defaults to the city name
- **Single-click to copy** — click any row to copy "City — Time" to the clipboard
- **Copy all** — hold the panel open while the scrubber is active to copy all times at once
- **Export/import settings** — back up all timezones and preferences to a JSON file or clipboard; restore on another Mac
- **Pin to desktop** — float the panel above all windows and drag it anywhere
- **Global hotkey** — set a keyboard shortcut to open the panel from anywhere
- **Start at login** — launches automatically with your Mac
- **Auto-update** — Sparkle delivers updates silently in the background
- **Ad-free, open source, no tracking** — location lookups go through Apple's geocoding service only when you add a timezone

## Install

### Homebrew (recommended)

```bash
brew tap tpak/tpak
brew install --cask meridian
```

Updates are delivered automatically via Sparkle (in-app). Because the cask sets `auto_updates true`, `brew upgrade` intentionally skips Meridian — Sparkle handles it.

### Direct download

Download the latest `.zip` from [GitHub Releases](https://github.com/tpak/Meridian/releases), unzip, and drag Meridian to your Applications folder.

Requires macOS 13 (Ventura) or later.

## Using Meridian

### Panel basics

Click the Meridian icon in your menu bar to open the panel. Press **⌘W** or click anywhere outside to close it.

Each row shows:
- **Location name** — the city or your custom label
- **Time** — current local time in that timezone (or scrubbed time when the slider is active)
- **Relative date** — "Today", "Tomorrow", "+1 day", etc., when the day differs from yours
- **Sunrise/sunset** — shown when coordinates are available and enabled in Appearance settings

### Adding timezones

1. Open **Settings** (⌘,) → **General** tab
2. Type a city, state, country, or timezone identifier in the search field
3. Select a result and click **Add**

The label defaults to the city name. To rename it, double-click the label in the list.

### Time scrubber

Drag the tick-mark slider at the bottom of the panel to move forward or backward in time — all clocks update together. The slider range is ±6 days by default (adjustable in Appearance settings).

- **`<` / `>`** — step 15 minutes backward or forward
- **↺** — reset to the current time

### Direct time entry

Double-click any time display in the panel. The field becomes editable — type a time in any of these formats:

| Input | Meaning |
|-------|---------|
| `7:30 PM` | 7:30 in the afternoon |
| `19:30` | 24-hour format |
| `7pm` | shorthand |
| `7` | on the hour |

Press **Enter** to jump the scrubber so that timezone shows the time you typed. All other clocks update accordingly. Press **Escape** or click away to cancel.

### Copying times

- **Single-click** any row — copies "City — Time" to the clipboard (works whether the panel is at current time or scrubbed time)
- **⌘C** in the panel — copies all visible times as a formatted list

### Favorites and the menubar

In **Settings → General**, click the star (★) next to a timezone to mark it as a favorite. Favorites appear in the compact menubar display alongside the Meridian icon. Un-star to remove.

### Pinning to the desktop

Right-click the Meridian icon in the menu bar and choose **Pin to Desktop**. The panel detaches from the menu bar, floats above all windows, and can be dragged anywhere on screen. Right-click the panel and choose **Unpin** to return it to the menu bar.

### Exporting and importing settings

Back up all your timezones and preferences as a JSON file — useful for restoring on a new Mac or syncing via dotfiles.

- **File → Export Settings…** (⌘⇧E) — saves to `~/.meridian/` by default; choose any location
- **File → Copy Settings to Clipboard** — copies the JSON directly to the clipboard
- **File → Import Settings…** — imports a previously exported file

The export includes all timezones and appearance preferences. `startAtLogin` is excluded and must be set manually after import.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘, | Open Settings |
| ⌘W | Close panel |
| ⌘C | Copy all times |
| ⌘⇧E | Export settings |

A **global hotkey** to open the panel from any app can be set in **Settings → General** (none by default).

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

### Release

```bash
git checkout main && git pull
make release VERSION=X.Y.Z
```

This handles everything: version bump, notarized build, GitHub release, Sparkle appcast update, and Homebrew cask update. See `scripts/release.sh` for details.

### Project Structure

User-facing names — product, bundle, scheme — are all "Meridian".

```
Meridian/
├── Meridian.xcodeproj      # Xcode project (scheme: Meridian)
├── App/                    # Localization, Info.plist, entitlements
├── Overall App/            # AppDelegate, DataStore, extensions
├── Panel/                  # Menu bar panel UI + data layer
├── Preferences/            # Settings (General, Appearance, About)
├── Dependencies/           # Vendored: DateTools, Solar
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
