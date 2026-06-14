# 08 — Theme & Appearance API Cheatsheet

> Read-only reconnaissance for v4 UI redesign. Source root: `Meridian-v4/Meridian/`.

---

## 1. Theme Enum (light / dark / system)

```swift
// DataStore.swift
enum Theme: Int, Codable, CaseIterable {
    case light  = 0
    case dark   = 1
    case system = 2
}
extension Theme: JSONNameDecodable {}   // jsonName == "light" / "dark" / "system"
```

### Storage & accessor

```swift
// UserDefaults key
UserDefaultKeys.themeKey = "defaultTheme"   // Int raw value

// DataStore typed accessor (DataStore.swift)
var theme: Theme {
    get { Theme(rawValue: userDefaults.integer(forKey: UserDefaultKeys.themeKey)) ?? .light }
    set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.themeKey) }
}

// Registered default (AppDefaults.swift)
UserDefaultKeys.themeKey: Theme.light.rawValue   // i.e. 0
```

### How theme changes propagate

`AppearanceViewController` owns an `NSPopUpButton` (`@IBOutlet var theme`) wired to `@IBAction func themeChanged(_ sender: NSPopUpButton)`.

```swift
// AppearanceViewController.swift – themeChanged path
@IBAction func themeChanged(_ sender: NSPopUpButton) {
    // 1. Saves new index to UserDefaults via the Cocoa bindings / direct write
    //    (index == Theme.rawValue; 0=light, 1=dark, 2=system)
    refresh(panel: false)                      // re-fires menubar timer etc.

    guard let panelController = PanelController.panel() else { return }
    panelController.refreshBackgroundView()    // redraws BackgroundPanelView
    panelController.updateTableContent()       // reloads table cells
}
```

There is **no NotificationCenter broadcast** for theme changes — consumers must call `updatePanelColor()` / `updateTableContent()` explicitly or react to `UserDefaults.didChangeNotification`.

```swift
// ParentPanelController.swift (base class)
func updatePanelColor() {
    window?.alphaValue = 1.0   // minimal base — subclass PanelController overrides
}

// PanelController.swift (concrete)
super.updatePanelColor()   // called in viewDidLoad
```

**`BackgroundPanelView`** is a custom `NSView` that fills with `NSColor.windowBackgroundColor` (semantic — adapts to dark/light automatically). No explicit `Theme` switch inside it.

```swift
// BackgroundPanelView.swift
NSColor.windowBackgroundColor.setFill()
```

**`TimezoneCellView`** applies appearance via `setupTheme()`:

```swift
private func setupTheme() {
    setTextColor(color: NSColor.labelColor)   // semantic — auto dark/light
    currentLocationIndicator.image = NSImage(systemSymbolName: "location.fill", ...)
    setupTextSize()
}

func setTextColor(color: NSColor) {
    [relativeDate, customName, time, sunriseSetTime].forEach { $0?.textColor = color }
    dstLabel.textColor = .gray
}
```

### System dark-mode observation

macOS dark/light switch is observed via `DistributedNotificationCenter` in `StatusItemHandler`:

```swift
// Foundation + Additions.swift
static let interfaceStyleDidChange = NSNotification.Name("AppleInterfaceThemeChangedNotification")

// UserDefaultKeys
static let appleInterfaceStyleKey = "AppleInterfaceStyle"

// StatusItemHandler.swift
DistributedNotificationCenter.default.publisher(for: .interfaceStyleDidChange)
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.respondToInterfaceStyleChange() }
    .store(in: &cancellables)

@objc func respondToInterfaceStyleChange() {
    updateCompactMenubar()    // refreshes menubar status item
}
```

`StatusItemView` (the compact menubar item view) detects dark mode per-draw via an `NSView` extension:

```swift
// StatusItemView.swift
extension NSView {
    var hasDarkAppearance: Bool {
        switch effectiveAppearance.name {
        case .darkAqua, .vibrantDark,
             .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }
}
```

Appearance-dependent text attribute caches are invalidated on:

```swift
override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cachedTimeAttributes = nil
    cachedTextFontAttributes = nil
    statusItemViewSetNeedsDisplay()
}
```

---

## 2. TeamAccent — F1 Livery Accent Color System

### Enum definition

```swift
// DataStore.swift
enum TeamAccent: String, Codable, CaseIterable {
    case alpine         // "0090FF" blue
    case astonMartin    // "006F62" green  ← default
    case audi           // "C00000" red
    case cadillac       // "DCA62E" gold   (substituted: real livery is near-black)
    case ferrari        // "DC0000" red
    case haas           // "ED1C24" red    (substituted: real livery is white)
    case mclaren        // "FF8000" orange
    case mercedes       // "00D2BE" teal
    case racingBulls    // "2647D8" blue
    case redBull        // "1E5BC6" blue
    case williams       // "005AFF" blue

    static let `default`: TeamAccent = .astonMartin

    var displayName: String { ... }    // "Aston Martin", "McLaren", etc.

    var accentColor: NSColor {
        // Hex → sRGB. Alpha is 0.85 on ALL teams for visual consistency.
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 0.85)
    }

    var jsonName: String { rawValue }   // stable export identifier
}
extension TeamAccent: JSONNameDecodable {}
```

### Storage & accessor

```swift
// UserDefaults key
UserDefaultKeys.teamAccent = "com.tpak.meridian.teamAccent"   // String raw value

// DataStore typed accessor
var teamAccent: TeamAccent {
    get {
        guard let raw = userDefaults.string(forKey: UserDefaultKeys.teamAccent),
              let team = TeamAccent(rawValue: raw) else {
            return TeamAccent.default
        }
        return team
    }
    set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.teamAccent) }
}

// Registered default
UserDefaultKeys.teamAccent: TeamAccent.default.rawValue   // "astonMartin"
```

### How to read the current accent color

```swift
let color: NSColor = DataStore.shared().teamAccent.accentColor
```

### AccentColorSwizzler — runtime NSColor.controlAccentColor override

```swift
// App/AccentColorSwizzler.swift
enum AccentColorSwizzler {
    static func install()   // idempotent, call once at app launch
}

// Swizzles +controlAccentColor → NSColor.mer_currentTeamAccentColor()
// which returns DataStore.shared().teamAccent.accentColor.
// Called from AppDelegate.applicationDidFinishLaunching.
```

**Limitation noted in code**: AppKit caches `NSDynamicSystemColor` resolutions per `NSAppearance`. Existing rendered surfaces don't repaint just from the swizzle. Some surfaces (popup highlights, segmented control fills, toolbar tab text) require a full app relaunch. The swizzle is still worthwhile for fresh-draw paths.

### Notification for accent color changes

```swift
// AccentColorSwizzler.swift
extension Notification.Name {
    static let accentColorDidChange = Notification.Name("com.tpak.meridian.accentColorDidChange")
}

// Posted by:
NSApplication.shared.mer_invalidateAccentEverywhere()
// → NotificationCenter.default.post(name: .accentColorDidChange, object: nil)

// Also posted directly by SettingsManager after import:
NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
```

### Surfaces that observe .accentColorDidChange

```swift
// PanelController.swift
NotificationCenter.default.publisher(for: .accentColorDidChange)
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.accentColorDidChange() }
    .store(in: &cancellables)

private func accentColorDidChange() {
    updateFloatModeUI()              // pin button contentTintColor
    applyTeamAccentToSliderControls()  // chevron + reset buttons
}

// OneWindowController.swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(refreshToolbarForAccentChange),
    name: .accentColorDidChange,
    object: nil
)
// refreshToolbarForAccentChange → setupToolbarImages() (rebuilds SF Symbol tints)
```

### Surfaces explicitly tinted with teamAccent.accentColor

| Surface | File | How |
|---------|------|-----|
| Pin button (float mode) | `PanelController.swift` | `pinButton?.contentTintColor = teamAccent.accentColor` |
| Slider chevron buttons | `ParentPanelController+ModernSlider.swift` | `goBackwardsButton?.contentTintColor = tint` |
| Slider reset button | `ParentPanelController+ModernSlider.swift` | `resetModernSliderButton?.contentTintColor = tint` |
| Slider fill (left of thumb) | `CustomSliderCell.swift` | `teamAccent.accentColor.setFill()` |
| All NSControl system accent surfaces | `AccentColorSwizzler.swift` | Via `+controlAccentColor` swizzle |
| Preferences toolbar icons | `OneWindowController.swift` | Template SF Symbol (system tints it via controlAccentColor) |

### teamAccentChanged flow

```swift
// AppearanceViewController.swift
@IBAction func teamAccentChanged(_ sender: NSPopUpButton) {
    let team = TeamAccent.allCases[sender.indexOfSelectedItem]
    DataStore.shared().teamAccent = team      // write UserDefaults
    NSApp.mer_invalidateAccentEverywhere()    // post .accentColorDidChange
    previewPanelTableView.reloadData()
    promptForRestart(applying: team)          // modal alert → quit+relaunch if user accepts
}
```

### Relaunch-for-accent flow

```swift
// AppearanceViewController.swift
private func promptForRestart(applying team: TeamAccent) {
    // NSAlert: "Restart Now" or "Apply at Next Launch"
    // On "Restart Now":
    UserDefaults.standard.set(true, forKey: UserDefaultKeys.reopenAppearanceOnLaunch)
    // spawns "open -n <bundle>", then NSApp.terminate(nil)
}

// AppDelegate.swift — on next launch:
private func reopenAppearanceIfRelaunchedForTeamAccent() {
    guard UserDefaults.standard.bool(forKey: UserDefaultKeys.reopenAppearanceOnLaunch) else { return }
    UserDefaults.standard.removeObject(forKey: UserDefaultKeys.reopenAppearanceOnLaunch)
    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.openAppearanceAfterRelaunch) {
        self.panelController.oneWindow?.openAppearancePane()
    }
}
```

```swift
// UserDefaultKeys for accent relaunch flag
static let reopenAppearanceOnLaunch = "com.tpak.meridian.reopenAppearanceOnLaunch"
```

---

## 3. Asset Catalog — Media.xcassets

**Only one colorset exists:**

```
Media.xcassets/Accent Color.colorset
```

Contents (both light and dark variants are identical — the asset catalog value is a **neutral placeholder**, intentionally overridden by the swizzle at runtime):

```json
{
  "color-space": "srgb",
  "components": { "alpha": "0.350", "blue": "0.560", "green": "0.560", "red": "0.560" }
}
```

This gray is what AppKit would use for `controlAccentColor` if the swizzle were not installed. The swizzle replaces it entirely at runtime with `teamAccent.accentColor`.

**No other colorsets** (no semantic token colors, no dark-mode color pairs beyond what the system provides via `NSColor` semantic names).

---

## 4. Semantic NSColor Usage Across the App

All structural colors use AppKit semantics (auto-adapt to dark/light — no app-level switching needed):

| Color | Usage |
|-------|-------|
| `NSColor.labelColor` | Primary text in cells, preference labels |
| `NSColor.secondaryLabelColor` | Info labels, pin button (unfloated), accentColorInfoButton tint |
| `NSColor.windowBackgroundColor` | Panel background, preferences window, table backgrounds |
| `NSColor.controlBackgroundColor` | Rounded date view background |
| `NSColor.textBackgroundColor` | Timezone list table, search panel |
| `NSColor.quaternaryLabelColor` | Drag handle fill |
| `NSColor.systemYellow` | Sunrise icon tint |
| `NSColor.systemOrange` | Sunset icon tint |
| `NSColor.clear` | Panel window background, scrollview, menubar item backgrounds |

**Hard-coded (non-semantic) colors — gotchas for v4:**

```swift
// CustomSliderCell.swift — track background (left of filled portion)
NSColor(calibratedRed: 67.0/255.0, green: 138.0/255.0, blue: 250.0/255.0, alpha: 1.0)
// This is a hard-coded blue, NOT semantic. Visible contrast issue in dark mode.

// TimeMarkerViewItem.swift — timeline vertical rule
verticalLineView.layer?.backgroundColor = NSColor.lightGray.cgColor
// lightGray is not appearance-adaptive.

// NoTimezoneView.swift
messageField.textColor = .darkGray   // not adaptive
```

---

## 5. No ThemeManager / Themer / Token System Exists

There is **no** `Themer`, `ThemeManager`, `ColorToken`, `DesignToken`, or centralized color dictionary. Color decisions are made at point-of-use via:

1. AppKit semantic `NSColor` names (auto dark/light)
2. `DataStore.shared().teamAccent.accentColor` (F1 livery, runtime)
3. A handful of hardcoded literal colors (see above)

The v4 token system has **no existing abstraction to plug into**. The hook points for a token system would be:

- Replace the 3 hardcoded literal colors with token lookups
- Add a token → `NSColor` resolver that respects both `Theme` (light/dark/system) and `TeamAccent`
- The `Notification.Name.accentColorDidChange` broadcast pattern is already the right shape for propagating token changes; v4 can extend or repurpose it

---

## 6. SettingsManager Export/Import for Theme Keys

```swift
// SettingsManager.swift — V2 export keys
private enum V2Key {
    static let theme      = "theme"       // String jsonName: "light" / "dark" / "system"
    static let teamAccent = "teamAccent"  // String rawValue: "astonMartin", "ferrari", etc.
}

// Export
V2Key.theme:      store.theme.jsonName
V2Key.teamAccent: store.teamAccent.jsonName

// Import — v2
if let s = prefs[V2Key.theme] as? String, let t = Theme(jsonName: s) { store.theme = t }
if let s = prefs[V2Key.teamAccent] as? String, let team = TeamAccent(jsonName: s) {
    store.teamAccent = team
}
// After import: posts .accentColorDidChange and calls panel.updateTableContent()

// Import — v1 back-compat
if let v = prefs["defaultTheme"] as? Int { store.theme = Theme(rawValue: v) ?? .light }
// No v1 teamAccent (feature postdates v1)
```

---

## 7. Key Constants Summary

```swift
// UserDefaultKeys
static let themeKey              = "defaultTheme"
static let teamAccent            = "com.tpak.meridian.teamAccent"
static let reopenAppearanceOnLaunch = "com.tpak.meridian.reopenAppearanceOnLaunch"
static let appleInterfaceStyleKey = "AppleInterfaceStyle"

// Notification.Name
static let accentColorDidChange  = Notification.Name("com.tpak.meridian.accentColorDidChange")
static let interfaceStyleDidChange = NSNotification.Name("AppleInterfaceThemeChangedNotification")
```

---

## 8. What v4 Must Respect / Gotchas

1. **No runtime accent repaint for AppKit controls**: `NSPopUpButton`, `NSSegmentedControl`, `NSCheckbox`, focus rings, and toolbar tab text are all cached by AppKit and require app relaunch. The existing restart prompt in `AppearanceViewController.promptForRestart` is the only reliable mechanism. A v4 SwiftUI redesign might avoid this entirely since SwiftUI does not cache accent color the same way.

2. **Swizzle installs at launch**: `AccentColorSwizzler.install()` must run before any window is shown. If v4 keeps AppKit controls, the swizzle must remain.

3. **`Theme` raw values are stored as `Int`**: `0=light, 1=dark, 2=system`. The popup item order in the storyboard must match these indices or existing user settings will map to the wrong theme.

4. **`TeamAccent` raw values are the export-stable JSON identifiers**: Never rename a case without a migration. Current case names: `alpine`, `astonMartin`, `audi`, `cadillac`, `ferrari`, `haas`, `mclaren`, `mercedes`, `racingBulls`, `redBull`, `williams`.

5. **Three hardcoded non-adaptive colors** exist in `CustomSliderCell`, `TimeMarkerViewItem`, and `NoTimezoneView` — these will need token replacements in v4.

6. **`hasDarkAppearance`** on `NSView` is the app's only per-view dark-mode probe. It checks `effectiveAppearance.name` against four cases including high-contrast variants. Reuse or replicate for any custom-drawn surfaces.

7. **`Theme.system`** is stored but the app does NOT currently wire it to `NSApp.appearance = nil` programmatically. Dark/light adaptation happens purely through AppKit semantic colors — meaning the panel follows the system regardless of the `Theme` setting. The `Theme` enum is exposed in UI and logs but has limited mechanical effect beyond what the system does automatically.
