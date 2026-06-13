# 01 — Data Model + Store API Cheatsheet

> Source files:
> - `CoreModelKit/Sources/CoreModelKit/TimezoneData.swift`
> - `Overall App/DataStore.swift`
> - `Overall App/Strings.swift` (UserDefaultKeys)
> - `Overall App/AppDefaults.swift`
> - `Overall App/UserDefaults + KVOExtensions.swift`
> - `Overall App/Foundation + Additions.swift`

---

## TimezoneData

```swift
public class TimezoneData: NSObject, NSCoding, NSSecureCoding
```

`NSObject` subclass (non-struct) — required for `NSCoding`. Mutate properties directly; re-archive manually to persist.

### All Public Properties

```swift
public var customLabel: String?          // user-set display name; nil = use formattedAddress
public var formattedAddress: String?     // geocoded city/address string
public var placeID: String?             // UUID or Google place_id; also the equality key
public var timezoneID: String?          // IANA identifier e.g. "America/Denver"; default ""
public var latitude: Double?            // clamped to -90...90; nil or -0.0 = unknown
public var longitude: Double?           // clamped to -180...180; nil or -0.0 = unknown
public var nextUpdate: Date?            // scheduled sunrise/sunset recalculation date
public var sunriseTime: Date?           // cached solar result
public var sunsetTime: Date?            // cached solar result
public var isFavourite: Int             // 0 = not favourite, 1 = favourite (menubar-pinned)
public var isSunriseOrSunset = false   // transient display flag; not persisted
public var selectionType: SelectionType = .city
public var isSystemTimezone = false    // true → timezone() returns autoupdatingCurrent
public var overrideFormat: TimezoneOverride = .globalFormat
```

**Equality** is `placeID == other.placeID && timezoneID == other.timezoneID`.

### Nested Enums

```swift
public enum SelectionType: Int {
    case city     = 0   // geocoded via CLGeocoder
    case timezone = 1   // picked directly from TimeZone.knownTimeZoneIdentifiers
}

public enum DateDisplayType: Int {
    case panel = 0
    case menu  = 1
}

public enum TimezoneOverride: Int {
    case globalFormat                  = 0   // respects app-wide TimeFormat preference
    case twelveHourFormat              = 1
    case twentyFourFormat              = 2
    case twelveHourWithSeconds         = 4
    case twentyHourWithSeconds         = 5
    case twelveHourPrecedingZero       = 7
    case twelveHourPrecedingZeroSeconds = 8
    case twelveHourWithoutSuffix       = 10
    case twelveHourWithoutSuffixAndSeconds = 11
    case epochTime                     = 12
    // Note: raw values 3, 6, 9 are intentionally absent (legacy gaps)
}
```

### Key Methods

```swift
// Display label: customLabel → formattedAddress → timezoneID component → "Error"
public func formattedTimezoneLabel() -> String

// IANA identifier, respecting isSystemTimezone flag (read-only — does NOT mutate stored fields)
public func timezone() -> String

// Resolves overrideFormat against a global format NSNumber (see TimeFormat.rawValue)
public func timezoneFormat(_ currentFormat: NSNumber) -> String

// Whether the resolved format includes seconds
public func shouldShowSeconds(_ currentFormat: NSNumber) -> Bool

// True if the IANA tz is currently in DST
public func isDaylightSavings() -> Bool

// Set customLabel; empty string stores ModelConstants.emptyString (not nil)
public func setLabel(_ label: String)

// Integer-based override setter — use TimezoneOverride.rawValue directly on the property instead
public func setShouldOverrideGlobalTimeFormat(_ shouldOverride: Int)
```

### Construction

```swift
// 1. Empty (selectionType = .timezone, no coordinates)
let td = TimezoneData()

// 2. From geocoder result dictionary
let td = TimezoneData(with: [
    "customLabel": "...",
    "timezoneID": "America/Denver",
    "latitude": 39.7392,
    "longitude": -104.9903,
    "place_id": "ChIJz...",
    "formattedAddress": "Denver, CO"
])

// 3. Convenience factory (selectionType = .city)
let td = TimezoneData.make(
    timezoneID: "America/Denver",
    name: "Denver, CO",
    customLabel: "Home",
    latitude: 39.7392,
    longitude: -104.9903,
    placeIdentifier: "ChIJz..."
)
```

### Serialization (NSKeyedArchiver)

```swift
// Archive: use the extension in Foundation + Additions.swift
let blob: Data? = NSKeyedArchiver.secureArchive(with: timezoneData)

// Unarchive
let td: TimezoneData? = TimezoneData.customObject(from: blob)
```

`NSKeyedArchiver.secureArchive(with:)` wraps `NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding:true)`. `customObject(from:)` uses an explicit allowlist `[TimezoneData.self, NSString.self, NSNumber.self, NSDate.self]` — required for macOS 26.

### NSCoder Keys (for migration / custom decoders)

| Property | Coder key |
|---|---|
| `customLabel` | `"customLabel"` |
| `formattedAddress` | `"formattedAddress"` |
| `placeID` | `"place_id"` |
| `timezoneID` | `"timezoneID"` |
| `latitude` | `"latitude"` (as NSNumber) |
| `longitude` | `"longitude"` (as NSNumber) |
| `nextUpdate` | `"nextUpdate"` |
| `sunriseTime` | `"sunriseTime"` |
| `sunsetTime` | `"sunsetTime"` |
| `isFavourite` | `"isFavourite"` (Int) |
| `selectionType` | `"selectionType"` (Int rawValue) |
| `isSystemTimezone` | `"isSystemTimezone"` (Bool) |
| `overrideFormat` | `"overrideFormat"` (Int rawValue) |

`isSunriseOrSunset` is **not** persisted (transient display state).

---

## DateFormat constants

```swift
public enum DateFormat {
    public static let twelveHour                     = "h:mm a"
    public static let twelveHourWithSeconds          = "h:mm:ss a"
    public static let twentyFourHour                 = "HH:mm"
    public static let twentyFourHourWithSeconds      = "HH:mm:ss"
    public static let twelveHourWithZero             = "hh:mm a"
    public static let twelveHourWithZeroSeconds      = "hh:mm:ss a"
    public static let twelveHourWithoutSuffix        = "hh:mm"
    public static let twelveHourWithoutSuffixAndSeconds = "hh:mm:ss"
    public static let epochTime                      = "epoch"
}
```

`TimezoneData.values` maps `NSNumber` popup indices → format strings (used by `timezoneFormat(_:)`).

---

## ModelConstants (internal dictionary keys)

```swift
struct ModelConstants {
    static let customLabel     = "customLabel"
    static let timezoneName    = "formattedAddress"
    static let placeIdentifier = "place_id"
    static let timezoneID      = "timezoneID"
    static let emptyString     = ""
    static let latitude        = "latitude"
    static let longitude       = "longitude"
}
```

---

## DataStoring Protocol

```swift
protocol DataStoring: AnyObject {
    func timezones() -> [Data]                        // raw blobs, UserDefaults order
    func setTimezones(_ timezones: [Data]?)           // persist + refresh caches
    func menubarTimezones() -> [Data]                 // filtered: isFavourite == 1
    func timezoneObjects() -> [TimezoneData]          // decoded, UserDefaults order
    func menubarTimezoneObjects() -> [TimezoneData]   // decoded, isFavourite == 1
    func shouldDisplay(_ type: ViewType) -> Bool      // legacy entry point; delegates to typed accessors
    func retrieve(key: String) -> Any?               // raw UserDefaults.object(forKey:)
    func addTimezone(_ timezone: TimezoneData)        // archive + append + persist
    func removeLastTimezone()                         // pop last + persist
    func timezoneFormat() -> NSNumber                // NSNumber(TimeFormat.rawValue)
    func isBufferRequiredForTwelveHourFormats() -> Bool
    func shouldShowDateInMenubar() -> Bool
    func shouldShowDayInMenubar() -> Bool
}
```

`ViewType` enum (used by `shouldDisplay(_:)`):
```swift
enum ViewType {
    case futureSlider, twelveHour, sunrise, showAppInForeground,
         appDisplayOptions, dateInMenubar, placeInMenubar, dayInMenubar
}
```

---

## DataStore (concrete singleton)

```swift
class DataStore: NSObject, DataStoring
```

### Singleton Accessor

```swift
// Read-only; initialized once at app start via DataStore(with: UserDefaults.standard)
class func shared() -> DataStore

// DI in tests:
let store = DataStore(with: someUserDefaults)
```

### Typed Preference Accessors (get/set on DataStore instance)

```swift
// Booleans
var showSunriseSunset: Bool      // key: "showSunriseSunset"
var showFutureSlider: Bool       // key: "showFutureSlider"
var showDayInMenubar: Bool       // key: "showDayInMenubar"
var showDateInMenubar: Bool      // key: "showDateInMenubar"
var showPlaceNameInMenubar: Bool // key: "showPlaceNameInMenubar"
var floatOnTop: Bool             // key: "floatOnTop"

// Enums
var theme: Theme                          // key: UserDefaultKeys.themeKey = "defaultTheme"
var relativeDateDisplay: RelativeDateDisplay  // key: "relativeDate"
var appPresentation: AppPresentation      // key: "com.tpak.meridian.appDisplayOptions"
var timeFormat: TimeFormat                // key: "timeFormat"
var teamAccent: TeamAccent               // key: "com.tpak.meridian.teamAccent" (String-backed)
```

All setters write directly to `UserDefaults` (no separate persist step needed).

---

## Typed Preference Enums (DataStore.swift)

```swift
enum Theme: Int, Codable, CaseIterable {
    case light = 0, dark = 1, system = 2
}

enum RelativeDateDisplay: Int, Codable, CaseIterable {
    case relative = 0, actual = 1, date = 2, hidden = 3
}

enum AppPresentation: Int, Codable, CaseIterable {
    case menubarOnly = 0, menubarAndDock = 1
}

enum TimeFormat: Int, Codable, CaseIterable {
    case twelveHour                      = 0
    case twentyFourHour                  = 1
    case twelveHourWithSeconds           = 3
    case twentyFourHourWithSeconds       = 4
    case twelveHourWithLeadingZero       = 6
    case twelveHourWithLeadingZeroAndSeconds = 7
    case twelveHourWithoutAmPm           = 9
    case twelveHourWithoutAmPmAndSeconds = 10
    case epoch                           = 11
    // 2, 5, 8 are intentionally absent (disabled separator rows)
}

enum TeamAccent: String, Codable, CaseIterable {
    case alpine, astonMartin, audi, cadillac, ferrari, haas,
         mclaren, mercedes, racingBulls, redBull, williams

    static let `default`: TeamAccent = .astonMartin

    var displayName: String { ... }   // e.g. "Aston Martin"
    var accentColor: NSColor { ... }  // sRGB, alpha 0.85
    var jsonName: String { rawValue } // stable export identifier
}
```

`RelativeDayDisplay` (in TimezoneData.swift, for per-row display):
```swift
public enum RelativeDayDisplay: Int {
    case relativeDay = 0, dayName = 1, dateFormat = 2, hidden = 3
}
```

---

## UserDefaultKeys — Full Reference

```swift
// Timezone list
static let defaultPreferenceKey  = "defaultPreferences"   // [Data] blob array

// Time format (modernized)
static let timeFormat            = "timeFormat"            // TimeFormat.rawValue Int

// Display booleans (modernized, post-migration)
static let showSunriseSunset     = "showSunriseSunset"
static let showFutureSlider      = "showFutureSlider"
static let showDayInMenubar      = "showDayInMenubar"
static let showDateInMenubar     = "showDateInMenubar"
static let showPlaceNameInMenubar = "showPlaceNameInMenubar"
static let floatOnTop            = "floatOnTop"

// Enum preferences
static let themeKey              = "defaultTheme"          // Theme.rawValue Int
static let relativeDateKey       = "relativeDate"          // RelativeDateDisplay.rawValue Int
static let appDisplayOptions     = "com.tpak.meridian.appDisplayOptions"  // AppPresentation Int

// Team accent (String)
static let teamAccent            = "com.tpak.meridian.teamAccent"

// Scalar prefs
static let userFontSizePreference = "userFontSize"         // Int (default 4)
static let futureSliderRange      = "sliderDayRange"       // Int (default 6 days)
static let truncateTextLength     = "truncateTextLength"   // Int (default 30)
static let startAtLogin           = "startAtLogin"         // Int 0/1

// Feature flags
static let betaUpdatesEnabled     = "com.tpak.meridian.betaUpdatesEnabled"
static let debugLoggingEnabled    = "com.tpak.meridian.debugLoggingEnabled"
static let tahoeOnboardingShown   = "com.tpak.meridian.tahoeOnboardingShown"

// Migration guard flags
static let boolSemanticsMigrationV1 = "com.tpak.meridian.boolSemanticsMigrationV1"
static let homeRowMigrationV1       = "com.tpak.meridian.homeRowMigrationV1"
static let legacyArtifactCleanupV1  = "com.tpak.meridian.legacyArtifactCleanupV1"

// Legacy keys (deprecated post-migration, do not use)
// selectedTimeZoneFormatKey, sunriseSunsetTime, displayFutureSliderKey,
// showDayInMenu, showDateInMenu, showPlaceInMenu, showAppInForeground
```

---

## How Favorites (Menubar Pins) Work

`isFavourite` is an `Int` on `TimezoneData` (not `Bool`). Value `1` = pinned in menubar.

```swift
// Read all pinned timezones
let pinned: [TimezoneData] = DataStore.shared().menubarTimezoneObjects()

// Pin a timezone:
someTimezoneData.isFavourite = 1
// Then re-serialize all timezones and persist:
let blobs = DataStore.shared().timezoneObjects()
    .map { td in
        // mutate and re-archive
        NSKeyedArchiver.secureArchive(with: td)!
    }
DataStore.shared().setTimezones(blobs)
```

`menubarTimezones()` / `menubarTimezoneObjects()` are derived caches — recomputed inside `setTimezones(_:)` automatically. No separate "menubar list" is stored in UserDefaults.

---

## How to Mutate and Persist

The list is stored as `[Data]` (archived blobs) in UserDefaults under `"defaultPreferences"`. There is **no automatic binding** — every mutation requires re-archiving:

```swift
// Pattern: read → decode → mutate → re-archive → setTimezones
var blobs = DataStore.shared().timezones()
if let td = TimezoneData.customObject(from: blobs[index]) {
    td.customLabel = "New Label"
    if let newBlob = NSKeyedArchiver.secureArchive(with: td) {
        blobs[index] = newBlob
    }
    DataStore.shared().setTimezones(blobs)
}
// setTimezones persists to UserDefaults AND rebuilds all four caches atomically.
```

Adding:
```swift
DataStore.shared().addTimezone(newTimezoneData)   // archives + appends + persists
```

Removing last (undo support):
```swift
DataStore.shared().removeLastTimezone()
```

For arbitrary index removal, callers filter `timezones()`, then call `setTimezones(_:)`.

---

## Change Observation

Three patterns in use:

### 1. `UserDefaults.didChangeNotification` (Combine)
```swift
NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
    .sink { [weak self] _ in self?.refreshUI() }
    .store(in: &cancellables)
```
Used by `StatusItemHandler` (menubar redraw) and `AboutView`.

### 2. KVO on `UserDefaults` `@objc dynamic` properties
```swift
// UserDefaults + KVOExtensions.swift declares:
@objc dynamic var userFontSize: Int   // key "userFontSize"
@objc dynamic var sliderDayRange: Int // key "sliderDayRange"
@objc dynamic var floatOnTop: Bool    // key "floatOnTop"
@objc dynamic var showFutureSlider: Bool // key "showFutureSlider"

// Observe (Combine):
UserDefaults.standard.publisher(for: \.floatOnTop)
    .sink { [weak self] val in ... }
    .store(in: &cancellables)
```
**Gotcha**: property name must exactly match the UserDefaults key string for KVO notifications to fire. Dotted keys (like `com.tpak.meridian.*`) cannot be observed this way.

### 3. `NSNotification.Name.customLabelChanged`
```swift
// Posted by ParentPanelController after a label edit:
NotificationCenter.default.post(name: .customLabelChanged, object: nil)

// Observed by PreferencesViewController to reload the table:
NotificationCenter.default.publisher(for: .customLabelChanged)
    .sink { [weak self] _ in self?.reloadTableData() }
    .store(in: &cancellables)
```

---

## AppDefaults — Initialization and Migrations

Call order on launch (in `AppDefaults.initialize(with:defaults:)`):

1. `runBoolSemanticsMigration(on:)` — one-time; converts legacy inverted-bool/int keys to typed schema
2. `runLegacyArtifactCleanupV1(on:)` — one-time; removes `com.abhishek.*` and `Clocker*` artifacts
3. `defaults.register(defaults: defaultsDictionary())` — registers fallback values for all keys
4. `runHomeRowMigrationV1(on:defaults:)` — one-time; heals `isSystemTimezone` drift; returns `[Data]` that caller must pass to `store.setTimezones(_:)`

All migrations are idempotent (guarded by their own boolean flags in UserDefaults).

Registered defaults:
```swift
// Key: default value
"defaultTheme": 0           // Theme.light
"relativeDate": 0           // RelativeDateDisplay.relative
appDisplayOptions: 0        // AppPresentation.menubarOnly
"showSunriseSunset": false
"showFutureSlider": true
"showDayInMenubar": true
"showDateInMenubar": false
"showPlaceNameInMenubar": true
"floatOnTop": false
"timeFormat": 0             // TimeFormat.twelveHour
"userFontSize": 4
"sliderDayRange": 6
"truncateTextLength": 30
"startAtLogin": 0
teamAccent: "astonMartin"
tahoeOnboardingShown: false
```

---

## MockDataStore (for DI in tests)

```swift
class MockDataStore: DataStoring {
    var storedTimezones: [Data] = []
    var preferences: [String: Any] = [:]
    var viewTypeDisplayPreferences: [ViewType: Bool] = [:]
    // Full protocol conformance; timezoneFormat() reads preferences["is24HourFormatSelected"]
}
```

---

## JSONNameDecodable Protocol (SettingsManager export)

All preference enums conform via `extension Theme/RelativeDateDisplay/AppPresentation/TimeFormat: JSONNameDecodable` and `extension TeamAccent: JSONNameDecodable`. Provides:
```swift
var jsonName: String { get }        // stable export name (defaults to Swift case name)
init?(jsonName: String)             // decode from export
```
`TeamAccent.jsonName` overrides to `rawValue` explicitly for stability.

---

## Gotchas for v4 UI Rewrite

1. **`isFavourite` is `Int`, not `Bool`** — always compare `== 1`, never `== true`.
2. **`isSunriseOrSunset` is transient** — it is NOT encoded/decoded; must be recalculated on each data load.
3. **`timezone()` is read-only** — the old code mutated `timezoneID` inside this method; the current implementation does NOT. `isSystemTimezone == true` rows read `TimeZone.autoupdatingCurrent.identifier` at runtime without touching stored fields.
4. **No automatic persistence** — `TimezoneData` mutations must be manually archived and passed to `setTimezones(_:)`.
5. **`setTimezones(_:)` is the single write point** — it atomically persists to UserDefaults and rebuilds all four caches (`cachedTimezones`, `cachedMenubarTimezones`, `cachedTimezoneObjects`, `cachedMenubarTimezoneObjects`).
6. **`TimeFormat` rawValues have gaps** (2, 5, 8 absent) — these correspond to disabled separator rows in `NSPopUpButton`; never construct `TimeFormat(rawValue: 2/5/8)`.
7. **KVO requires key-matching property names** — `@objc dynamic var floatOnTop` works because the key string is `"floatOnTop"`. Dotted-key preferences (`com.tpak.meridian.*`) cannot be KVO-observed this way; use `UserDefaults.didChangeNotification` instead.
8. **`DataStore.shared()` returns a `DataStore`, not `DataStoring`** — the typed preference accessors (`var theme`, `var timeFormat`, etc.) are on `DataStore` specifically, not on the protocol. Cast if you hold a `DataStoring` reference from DI.
9. **`customObject(from:)` returns `TimezoneData()` (not nil) for nil input** — guard on the input `Data?` being non-nil before trusting the result; a nil blob produces a blank `TimezoneData`.
10. **`timezoneID` is `String?`** (default `""`) — check both `!= nil` and `!isEmpty` before use; `timezone()` handles this and falls back to `autoupdatingCurrent`.
