# 06 — Preferences Storage: UserDefaultKeys, AppDefaults, Typed Accessors, SettingsManager

Sources read:
- `Overall App/Strings.swift`
- `Overall App/AppDefaults.swift`
- `Overall App/UserDefaults + KVOExtensions.swift`
- `Overall App/DataStore.swift` (typed accessors + enums)
- `Overall App/SettingsManager.swift`

---

## 1. UserDefaultKeys — Every Constant

All cases are `static let` on `enum UserDefaultKeys` (no raw value, namespace-only enum).

### Modernized typed-storage keys (current, post-issue-#97)

| Constant | String value | Type | Default | Purpose |
|---|---|---|---|---|
| `showSunriseSunset` | `"showSunriseSunset"` | `Bool` | `false` | Show sunrise/sunset time in panel |
| `showFutureSlider` | `"showFutureSlider"` | `Bool` | `true` | Show time-travel slider in panel |
| `showDayInMenubar` | `"showDayInMenubar"` | `Bool` | `true` | Show day abbreviation (Mon/Tue) in menubar |
| `showDateInMenubar` | `"showDateInMenubar"` | `Bool` | `false` | Show date (May 8) in menubar |
| `showPlaceNameInMenubar` | `"showPlaceNameInMenubar"` | `Bool` | `true` | Show place name in menubar |
| `floatOnTop` | `"floatOnTop"` | `Bool` | `false` | Panel floats above all windows (dock mode) |
| `timeFormat` | `"timeFormat"` | `Int` (TimeFormat.rawValue) | `TimeFormat.twelveHour.rawValue` (0) | Time display format |

### Already-correct enum keys (unchanged keys, never migrated)

| Constant | String value | Type | Default | Purpose |
|---|---|---|---|---|
| `themeKey` | `"defaultTheme"` | `Int` (Theme.rawValue) | `Theme.light.rawValue` (0) | App color theme |
| `relativeDateKey` | `"relativeDate"` | `Int` (RelativeDateDisplay.rawValue) | `RelativeDateDisplay.relative.rawValue` (0) | Date display mode |
| `appDisplayOptions` | `"com.tpak.meridian.appDisplayOptions"` | `Int` (AppPresentation.rawValue) | `AppPresentation.menubarOnly.rawValue` (0) | Menubar-only vs menubar+dock |

### Scalar preferences (Int, not enum-backed)

| Constant | String value | Type | Default | Purpose |
|---|---|---|---|---|
| `userFontSizePreference` | `"userFontSize"` | `Int` | `4` | Panel font size index |
| `futureSliderRange` | `"sliderDayRange"` | `Int` | `6` | Max ±days for time-travel slider |
| `truncateTextLength` | `"truncateTextLength"` | `Int` | `30` | Max chars before truncation |
| `startAtLogin` | `"startAtLogin"` | `Int` (0/1 legacy) | `0` | Launch at login (also via SMAppService) |

### Feature/namespaced keys

| Constant | String value | Type | Default | Purpose |
|---|---|---|---|---|
| `teamAccent` | `"com.tpak.meridian.teamAccent"` | `String` (TeamAccent.rawValue) | `"astonMartin"` | F1 team accent color |
| `debugLoggingEnabled` | `"com.tpak.meridian.debugLoggingEnabled"` | `Bool` | (not in defaults dict, effectively false) | Verbose OSLog output |
| `betaUpdatesEnabled` | `"com.tpak.meridian.betaUpdatesEnabled"` | `Bool` | (not in defaults dict, effectively false) | Opt-in Sparkle beta channel |
| `tahoeOnboardingShown` | `"com.tpak.meridian.tahoeOnboardingShown"` | `Bool` | `false` | macOS 26 menubar block dialog suppressor |
| `reopenAppearanceOnLaunch` | `"com.tpak.meridian.reopenAppearanceOnLaunch"` | `Bool` | (not registered) | Re-open Appearance tab after team relaunch |

### One-time migration flags (never read by UI, only migration guards)

| Constant | String value | Purpose |
|---|---|---|
| `boolSemanticsMigrationV1` | `"com.tpak.meridian.boolSemanticsMigrationV1"` | Guards `runBoolSemanticsMigration` |
| `homeRowMigrationV1` | `"com.tpak.meridian.homeRowMigrationV1"` | Guards `runHomeRowMigrationV1` |
| `legacyArtifactCleanupV1` | `"com.tpak.meridian.legacyArtifactCleanupV1"` | Guards `runLegacyArtifactCleanupV1` |

### Internal/model keys (not UI preferences)

| Constant | String value | Purpose |
|---|---|---|
| `defaultPreferenceKey` | `"defaultPreferences"` | `[Data]` blob array of all timezones |
| `timezoneName` | `"formattedAddress"` | Per-timezone formatted address |
| `customLabel` | `"customLabel"` | Per-timezone user label |
| `timezoneID` | `"timezoneID"` | Per-timezone IANA id |
| `placeIdentifier` | `"place_id"` | Per-timezone place id |
| `latitude` | `"latitude"` | Per-timezone coordinate |
| `longitude` | `"longitude"` | Per-timezone coordinate |
| `nextUpdate` | `"nextUpdate"` | Scheduled next Sparkle check |
| `dragSessionKey` | `"public.text"` | Drag-and-drop UTI |
| `testingLaunchArgument` | `"isUITesting"` | UI test detection |
| `appleInterfaceStyleKey` | `"AppleInterfaceStyle"` | System dark mode detection |

---

## 2. Typed Enums

All in `DataStore.swift`. All are `Int`-backed (`CaseIterable`) except `TeamAccent` (String-backed).

### `Theme: Int, CaseIterable`
```swift
enum Theme: Int, Codable, CaseIterable {
    case light = 0
    case dark  = 1
    case system = 2
}
// jsonName (export): "light" | "dark" | "system"
```

### `RelativeDateDisplay: Int, CaseIterable`
```swift
enum RelativeDateDisplay: Int, Codable, CaseIterable {
    case relative = 0  // "Yesterday", "Today", "Tomorrow"
    case actual   = 1  // "+1 day", "-2 days"
    case date     = 2  // "May 8"
    case hidden   = 3  // not shown
}
// jsonName: "relative" | "actual" | "date" | "hidden"
```

### `AppPresentation: Int, CaseIterable`
```swift
enum AppPresentation: Int, Codable, CaseIterable {
    case menubarOnly    = 0
    case menubarAndDock = 1
}
// jsonName: "menubarOnly" | "menubarAndDock"
```

### `TimeFormat: Int, CaseIterable`
```swift
// Indices match popup item order; 2/5/8 are disabled separator rows (no case).
enum TimeFormat: Int, Codable, CaseIterable {
    case twelveHour                        = 0   // "1:00 PM"
    case twentyFourHour                    = 1   // "13:00"
    case twelveHourWithSeconds             = 3   // "1:00:00 PM"
    case twentyFourHourWithSeconds         = 4   // "13:00:00"
    case twelveHourWithLeadingZero         = 6   // "01:00 PM"
    case twelveHourWithLeadingZeroAndSeconds = 7 // "01:00:00 PM"
    case twelveHourWithoutAmPm             = 9   // "1:00"
    case twelveHourWithoutAmPmAndSeconds   = 10  // "1:00:00"
    case epoch                             = 11  // Unix timestamp
}
// jsonName: "twelveHour" | "twentyFourHour" | "twelveHourWithSeconds" | etc.
```

### `TeamAccent: String, CaseIterable`
```swift
enum TeamAccent: String, Codable, CaseIterable {
    case alpine, astonMartin, audi, cadillac, ferrari, haas,
         mclaren, mercedes, racingBulls, redBull, williams

    static let `default`: TeamAccent = .astonMartin

    var displayName: String { ... }   // "Aston Martin", "Red Bull Racing", etc.
    var accentColor: NSColor { ... }  // sRGB, alpha 0.85
    var jsonName: String { rawValue } // e.g. "astonMartin"
}
```

---

## 3. DataStore Typed Accessors

Singleton: `DataStore.shared()` → `DataStore`.
All accessors read/write `UserDefaults.standard` under the modernized keys.

```swift
// Bool accessors
var showSunriseSunset: Bool      // get/set  key: "showSunriseSunset"
var showFutureSlider: Bool       // get/set  key: "showFutureSlider"
var showDayInMenubar: Bool       // get/set  key: "showDayInMenubar"
var showDateInMenubar: Bool      // get/set  key: "showDateInMenubar"
var showPlaceNameInMenubar: Bool // get/set  key: "showPlaceNameInMenubar"
var floatOnTop: Bool             // get/set  key: "floatOnTop"

// Enum accessors
var theme: Theme                           // get/set  key: "defaultTheme"
var relativeDateDisplay: RelativeDateDisplay // get/set  key: "relativeDate"
var appPresentation: AppPresentation       // get/set  key: "com.tpak.meridian.appDisplayOptions"
var timeFormat: TimeFormat                 // get/set  key: "timeFormat"
var teamAccent: TeamAccent                 // get/set  key: "com.tpak.meridian.teamAccent"
```

Convenience helpers on `DataStore`:
```swift
func shouldDisplay(_ type: ViewType) -> Bool   // delegates to typed accessors
func shouldShowDateInMenubar() -> Bool         // == showDateInMenubar
func shouldShowDayInMenubar() -> Bool          // == showDayInMenubar
func timezoneFormat() -> NSNumber              // NSNumber(value: timeFormat.rawValue)
func isBufferRequiredForTwelveHourFormats() -> Bool  // true for formats 0,3,4,6,7
```

### `ViewType` enum (legacy dispatch enum, still used in some call sites)
```swift
enum ViewType {
    case futureSlider       // → showFutureSlider
    case twelveHour         // → timeFormat == .twelveHour
    case sunrise            // → showSunriseSunset
    case showAppInForeground // → floatOnTop
    case appDisplayOptions  // → appPresentation == .menubarOnly
    case dateInMenubar      // → showDateInMenubar
    case placeInMenubar     // → showPlaceNameInMenubar
    case dayInMenubar       // → showDayInMenubar
}
```

---

## 4. KVO-Observable UserDefaults Extensions

Defined in `UserDefaults + KVOExtensions.swift`. Property name MUST match the UserDefaults key string for KVO to fire:

```swift
extension UserDefaults {
    @objc dynamic var userFontSize: Int    // key: "userFontSize"        — @objc KVO
    @objc dynamic var sliderDayRange: Int  // key: "sliderDayRange"      — @objc KVO
    @objc dynamic var floatOnTop: Bool     // key: "floatOnTop"          — @objc KVO
    @objc dynamic var showFutureSlider: Bool // key: "showFutureSlider"  — @objc KVO
}
```

**Gotcha**: KVO subscribers in `PanelController`/`ParentPanelController` use Combine and watch these keypaths on `UserDefaults.standard`. Adding new KVO-observable prefs requires both matching key string and property name.

---

## 5. AppDefaults — Registered Defaults

Called once at startup: `AppDefaults.initialize(with: store, defaults: UserDefaults.standard)`

```swift
// Registered via defaults.register(defaults:):
"defaultTheme"                          → Theme.light.rawValue            (0)
"relativeDate"                          → RelativeDateDisplay.relative.rawValue (0)
"com.tpak.meridian.appDisplayOptions"   → AppPresentation.menubarOnly.rawValue (0)
"showSunriseSunset"                     → false
"showFutureSlider"                      → true
"showDayInMenubar"                      → true
"showDateInMenubar"                     → false
"showPlaceNameInMenubar"                → true
"floatOnTop"                            → false
"timeFormat"                            → TimeFormat.twelveHour.rawValue   (0)
"startAtLogin"                          → 0
"userFontSize"                          → 4
"sliderDayRange"                        → 6
"truncateTextLength"                    → 30
"com.tpak.meridian.teamAccent"          → TeamAccent.default.rawValue      ("astonMartin")
"com.tpak.meridian.tahoeOnboardingShown" → false
```

### Migration order (critical — runs before `register(defaults:)`)
1. `runBoolSemanticsMigration` — converts legacy inverted-bool keys to typed schema
2. `runLegacyArtifactCleanupV1` — purges `com.abhishek.*` and `Clocker*` keys
3. `register(defaults:)` — sets fallbacks for any unset key
4. `runHomeRowMigrationV1` — heals `isSystemTimezone` flag drift on timezone rows

---

## 6. Bool-Semantics Migration Caveat

**The single most important gotcha for any UI rewrite:**

Legacy keys (pre-issue-#97) used **inverted int semantics**: `0 = show`, `1 = hide`. The modernized keys use **normal bool semantics**: `true = show`, `false = hide`. The migration runs once (guarded by `boolSemanticsMigrationV1`) and rewrites the values into the new keys, deleting the old ones. After migration, only the modernized keys exist.

Legacy key → Modern key mapping:
```
"showSunriseSetTime"       (inverted Int) → "showSunriseSunset"       (Bool)
"displayFutureSlider"      (inverted Int) → "showFutureSlider"        (Bool)
"showDay"                  (inverted Int) → "showDayInMenubar"        (Bool)
"showDate"                 (inverted Int) → "showDateInMenubar"       (Bool)
"showPlaceName"            (inverted Int) → "showPlaceNameInMenubar"  (Bool)
"displayAppAsForegroundApp" (non-inv Int, 1=float) → "floatOnTop"     (Bool)
"is24HourFormatSelected"   (Int)          → "timeFormat"              (Int, same value)
```

**Do NOT read legacy key names in new code.** Use the `DataStore` typed accessors exclusively.

---

## 7. SettingsManager JSON Schema (v2)

Export file: `~/.meridian/meridian_settings.json` (or user-chosen path).

### Top-level structure

```json
{
  "version": 2,
  "timezones": ["<base64-encoded NSKeyedArchiver blob>", ...],
  "startAtLogin": true,
  "preferences": { ... },
  "sparkle": { ... }
}
```

### `preferences` object (v2 keys — stable, frozen across releases)

```json
{
  "showSunriseSunset":     false,
  "showFutureSlider":      true,
  "showDayInMenubar":      true,
  "showDateInMenubar":     false,
  "showPlaceNameInMenubar": true,
  "floatOnTop":            false,
  "theme":                 "light",
  "relativeDateDisplay":   "relative",
  "appPresentation":       "menubarOnly",
  "timeFormat":            "twelveHour",
  "userFontSize":          4,
  "truncateTextLength":    30,
  "futureSliderRange":     6,
  "debugLoggingEnabled":   false,
  "betaUpdatesEnabled":    false,
  "teamAccent":            "astonMartin"
}
```

Enum values are **named case strings** (not raw ints). Import: `TimeFormat(jsonName: s)`, `Theme(jsonName: s)`, etc.

### `sparkle` object

```json
{
  "automaticallyChecksForUpdates":   true,
  "automaticallyDownloadsUpdates":   false,
  "updateCheckIntervalSeconds":      86400.0
}
```

Note: Applied to live `SPUUpdater` instance, not directly to UserDefaults.

### `startAtLogin`
Boolean. Applied via `StartupManager().toggleLogin(Bool)` (SMAppService), **not** just writing UserDefaults.

### v1 back-compat
v1 exports (`version: 1`) used inverted ints and legacy key names. `applyV1Preferences` undoes the inversion on import. The v1 keys `com.tpak.meridian.menubarCompactMode` and v2 `menubarMode` are silently dropped (standard mode removed in v2.21.4).

---

## 8. JSONNameDecodable Protocol

Conforming enums get stable string export names and failable `init?(jsonName:)`:

```swift
protocol JSONNameDecodable: CaseIterable {
    var jsonName: String { get }              // default: String(describing: self) == case name
}
extension JSONNameDecodable {
    init?(jsonName: String) { ... }           // reverse lookup by jsonName
}

// Conformers:
extension Theme: JSONNameDecodable {}
extension RelativeDateDisplay: JSONNameDecodable {}
extension AppPresentation: JSONNameDecodable {}
extension TimeFormat: JSONNameDecodable {}
extension TeamAccent: JSONNameDecodable {}    // overrides jsonName to use rawValue
```

---

## 9. Quick-Reference: Reading/Writing Preferences

```swift
let store = DataStore.shared()

// Read
let isSunriseOn   = store.showSunriseSunset         // Bool
let format        = store.timeFormat                 // TimeFormat
let theme         = store.theme                      // Theme
let sliderRange   = UserDefaults.standard.integer(forKey: UserDefaultKeys.futureSliderRange) // Int

// Write
store.showDayInMenubar = true
store.timeFormat = .twentyFourHour
store.theme = .dark
UserDefaults.standard.set(10, forKey: UserDefaultKeys.futureSliderRange)

// Observe via Combine (KVO-compatible)
UserDefaults.standard.publisher(for: \.floatOnTop)
    .sink { isFloating in ... }

UserDefaults.standard.publisher(for: \.sliderDayRange)
    .sink { days in ... }
```

---

## 10. Gotchas for UI Rewrite

1. **Never read legacy keys** (`showSunriseSetTime`, `displayFutureSlider`, `showDay`, `showDate`, `showPlaceName`, `displayAppAsForegroundApp`, `is24HourFormatSelected`). They are deleted on first launch post-#97.
2. **`startAtLogin` requires `StartupManager`** — writing the UserDefaults key alone does not register/unregister the login item.
3. **KVO property name must match key string exactly** — `floatOnTop` and `showFutureSlider` on `UserDefaults` extension work because the property name == the key string. This constraint is documented in the Strings.swift comment block.
4. **`TimeFormat` has gaps**: raw values 2, 5, 8 have no enum case (they are separator rows in the popup). `TimeFormat(rawValue:)` returns `nil` for those indices.
5. **`teamAccent` is String-backed** (not Int). All other typed enums are Int-backed. `DataStore.teamAccent` getter has a nil-coalesce to `.astonMartin`.
6. **v2 JSON enum strings are case-name derived** (e.g. `"twelveHourWithSeconds"`, `"menubarAndDock"`). Changing a Swift enum case name is a breaking change for export files.
7. **`appDisplayOptions` key has a dotted name** (`"com.tpak.meridian.appDisplayOptions"`). NSUserDefaultsController storyboard bindings using `values.<key>` cannot traverse it — use the typed accessor instead.
8. **`debugLoggingEnabled` and `betaUpdatesEnabled` have no registered default** — they fall through to `false` via `bool(forKey:)` returning false for unregistered keys.
