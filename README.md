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
- **Keyboard shortcuts** — global hotkey to toggle the panel
- **Start at login** — launches automatically with your Mac
- **Ad-free & open source**

## Install

Download the latest release from [GitHub Releases](https://github.com/tpak/Meridian/releases).

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
make test         # Run all 112 unit tests
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
├── Clocker/                # Main app source (localization, Info.plist)
│   ├── Overall App/        # AppDelegate, DataStore, extensions
│   ├── Panel/              # Menu bar panel UI + data layer
│   ├── Preferences/        # Settings (General, Appearance, About)
│   └── Dependencies/       # Vendored: DateTools, Solar
├── CoreLoggerKit/          # SPM package — OSLog wrapper
├── CoreModelKit/           # SPM package — TimezoneData model
├── MeridianUnitTests/      # 112 unit tests
└── MeridianUITests/        # UI tests
```

## Contributing

Pull requests welcome. Please open an issue first to discuss larger changes.

## Origin

Meridian began as a fork of [Clocker](https://github.com/n0shake/Clocker) by [Abhishek Banthia](https://github.com/n0shake). Since forking, it has diverged significantly — Firebase removal, async/await migration, feature simplification, full rebrand to 100% Swift — and is now maintained independently.

Thank you to Abhishek for creating the original Clocker and releasing it under the MIT License.

## License

MIT License. See [LICENSE](LICENSE) for the full text.
