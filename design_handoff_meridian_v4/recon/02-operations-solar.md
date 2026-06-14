# 02 — Operations & Solar: Display/Computation Layer

**Files covered:**
- `Meridian/Panel/Data Layer/TimezoneDataOperations.swift`
- `Meridian/Dependencies/Solar.swift`
- `Meridian/Dependencies/Date Additions/Date+TimeAgo.swift`
- `Meridian/Dependencies/Date Additions/Date+Comparators.swift`
- `Meridian/Overall App/DateFormatterManager.swift`
- `Meridian/CoreModelKit/Sources/CoreModelKit/TimezoneData.swift` (enums + `timezoneFormat`)

---

## 1. `TimezoneDataOperations` — Class Overview

```swift
class TimezoneDataOperations {
    // MARK: - Init
    init(with timezone: TimezoneData, store: DataStoring)

    // MARK: - Public API
    func time(with sliderValue: Int) -> String
    func date(with sliderValue: Int, displayType: TimezoneData.DateDisplayType) -> String
    public func timeDifference() -> String
    func formattedSunriseTime(with sliderValue: Int) -> String
    func nextDaylightSavingsTransitionIfAvailable(with sliderValue: Int) -> String?
    func compactMenuTitle() -> String
    func compactMenuSubtitle() -> String
    func todaysDate(with sliderValue: Int, locale: Locale = Locale(identifier: "en-US")) -> String
    func saveObject(at index: Int = -1)
}
```

No `@MainActor`, no `async`. All methods are synchronous. Not a singleton — instantiate per row:

```swift
let ops = TimezoneDataOperations(with: timezoneData, store: DataStore.shared())
```

---

## 2. `sliderValue` — Units and Meaning

`sliderValue: Int` is an **offset in whole minutes** added to `Date()` (wall-clock now).

- `0` → current real time
- `+60` → 1 hour in the future
- `-1440` → 1 day in the past
- Range driven by `UserDefaultKeys.futureSliderRange` (key `"sliderDayRange"`); default configured in `AppDefaults`; UI exposes ±N days (default 6)

All time arithmetic uses:

```swift
TimezoneDataOperations.gregorianCalendar.date(byAdding: .minute, value: sliderValue, to: Date())
```

---

## 3. `time(with sliderValue:) -> String`

```swift
func time(with sliderValue: Int) -> String
```

- Adds `sliderValue` minutes to `Date()` using `gregorianCalendar`.
- Calls `dataObject.timezoneFormat(store.timezoneFormat())` to get the format string.
- Special case: if format == `DateFormat.epochTime` (`"epoch"`), returns Unix epoch integer as a string (`"\(Int(Date().timeIntervalSince1970 + offset))"`) — note it uses `Date()` not `newDate` for the epoch value.
- Otherwise formats via `DateFormatterManager.dateFormatterWithFormat(with: .none, format:..., timezoneIdentifier: dataObject.timezone(), locale: Locale.autoupdatingCurrent)`.
- Returns the formatted time string in the row's timezone.

---

## 4. `date(with sliderValue:displayType:) -> String`

```swift
func date(with sliderValue: Int, displayType: TimezoneData.DateDisplayType) -> String
```

**`TimezoneData.DateDisplayType`:**
```swift
public enum DateDisplayType: Int {
    case panel  // = 0
    case menu   // = 1
}
```

- For `.menu`: returns short weekday only — `shortWeekdayText(convertedDate)` → `DateFormatterManager.localizedSimpleFormatter("E").string(from:)` (e.g. "Thu").
- For `.panel`: reads `UserDefaultKeys.relativeDateKey` (`"relativeDate"`) as `NSNumber`, switches on `RelativeDayDisplay`:

**`RelativeDayDisplay`:**
```swift
public enum RelativeDayDisplay: Int {
    case relativeDay = 0   // "Today", "Yesterday", "Tomorrow", or full weekday name
    case dayName    = 1   // full weekday name always
    case dateFormat = 2   // "MMM d" date string
    case hidden     = 3   // returns ""
}
```

- `.relativeDay`: compares local weekday vs destination weekday → returns `"Today"`, `"Yesterday"`, `"Tomorrow"`, or full weekday name. Appends `timeDifference()`.
- `.dayName`: full weekday + `timeDifference()`.
- `.dateFormat`: `todaysDate(with:)` + `timeDifference()`.
- `.hidden`: returns `""`.

---

## 5. `timeDifference() -> String`

```swift
public func timeDifference() -> String
```

Returns a localized offset string like `", +3 hours"` or `", -45m"`.

**How it works:**
1. Formats `Date()` in local timezone as `"d MMM yyyy HH:mm:ss"`.
2. Formats `Date()` in the row's timezone as the same format.
3. Parses both strings back into `Date` objects using the same formatter (normalizing to a common reference).
4. Calls `Date.timeAgo(since:)` from DateTools.
5. Strips `" ago"` suffix, prepends `", +"` (timezone ahead) or `", -"` (timezone behind).
6. For English, appends sub-hour minutes: `"\(minuteDifference)m"`.
7. German (`"de"`) gets special handling (strips `"Vor "`, appends `" vor"` or `" zurück"`).
8. Returns `""` if the difference is < ~3 seconds (same timezone).

**Gotcha:** `timeDifference()` always computes relative to `sliderValue = 0` (real now), regardless of the `sliderValue` passed to `date(with:displayType:)`. It is NOT a function of the slider.

---

## 6. `nextDaylightSavingsTransitionIfAvailable(with sliderValue:) -> String?`

```swift
func nextDaylightSavingsTransitionIfAvailable(with sliderValue: Int) -> String?
```

- Returns `nil` if no DST transition, or if the next transition is > 8 days away, or if it already passed (< 0 days).
- Returns a string like:
  - `"Heads up: DST transition will occur in 3 days."` (plural `"days"`)
  - `"Heads up: DST transition will occur in 1 day."` (singular)
  - `"Heads up: DST transition will occur in 2 hours."` (when same-day)
  - `"Heads up: DST transition will occur in 1 hour."` (singular)
- Cache key: `"\(timezone)_\(startOfDay)"` — resets daily.
- Window: `dstDaysLookahead = 8` days, comparing `nextDaylightSavingTimeTransition` against slider-adjusted `Date()`.

---

## 7. `formattedSunriseTime(with sliderValue:) -> String`

```swift
func formattedSunriseTime(with sliderValue: Int) -> String
```

- Returns `""` if `dataObject.latitude == nil || dataObject.longitude == nil`.
- Calls `initializeSunriseSunset(with:)` to populate `dataObject.sunriseTime` / `dataObject.sunsetTime`.
- Selects: `dataObject.isSunriseOrSunset ? sunrise : sunset` — **`true` = nighttime → show sunrise; `false` = daytime → show sunset.**
- Formats with `sunriseTimeFormatter` (locale `"en_US"`) using `dataObject.timezoneFormat(store.timezoneFormat())` as the format string, timezone set to `dataObject.timezone()`.

### Sunrise/sunset init path (`initializeSunriseSunset`)

```swift
private func initializeSunriseSunset(with sliderValue: Int)
```

1. Guard for non-nil `latitude` / `longitude`.
2. Cache key: `"\(timezoneID)_\(startOfDay)"` — one Solar calculation per location per calendar day.
3. If not cached: builds `CLLocationCoordinate2D(latitude:longitude:)`, adds `sliderValue` minutes to `Date()`, initializes `Solar(for: adjustedDate, coordinate:)`.
4. On success: sets `dataObject.sunriseTime`, `dataObject.sunsetTime`, `dataObject.isSunriseOrSunset = solar.isNighttime`.
5. On failure (polar regions, bad coords): logs, caches `(nil, nil)`.

**Timezone of sunrise/sunset `Date` objects:** Solar returns times in **UTC**. The `Date` objects stored in `dataObject.sunriseTime` / `dataObject.sunsetTime` are UTC instants. The display formatter sets its `timeZone` to `dataObject.timezone()` so the string renders in the row's local timezone.

---

## 8. Solar API

```swift
public struct Solar {
    public let coordinate: CLLocationCoordinate2D
    public private(set) var date: Date

    // Official sunrise/sunset (zenith 90.83°)
    public private(set) var sunrise: Date?           // UTC Date, nil in polar regions
    public private(set) var sunset: Date?            // UTC Date, nil in polar regions

    // Civil twilight (zenith 96°)
    public private(set) var civilSunrise: Date?
    public private(set) var civilSunset: Date?

    // Nautical twilight (zenith 102°)
    public private(set) var nauticalSunrise: Date?
    public private(set) var nauticalSunset: Date?

    // Astronomical twilight (zenith 108°)
    public private(set) var astronomicalSunrise: Date?
    public private(set) var astronomicalSunset: Date?

    // Failable init — returns nil if coordinate is invalid
    public init?(for date: Date = Date(), coordinate: CLLocationCoordinate2D)

    // Convenience computed properties
    public var isDaytime: Bool      // sunrise <= date < sunset
    public var isNighttime: Bool    // !isDaytime
}
```

**How Solar calculates:**
- Pure math (USNO algorithm), no network.
- All intermediate and output `Date` objects are in **UTC** (calendar forced to `.gregorian` with `TimeZone(identifier: "UTC")`).
- `isNighttime` compares `date.timeIntervalSince1970` against `sunrise` and `sunset` time intervals. Returns `false` (not nighttime = daytime) if either is `nil`.

**Meridian only uses `solar.sunrise`, `solar.sunset`, and `solar.isNighttime`.**

```swift
// Example call
let coord = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522) // Paris
if let solar = Solar(for: Date(), coordinate: coord) {
    let sunriseUTC: Date? = solar.sunrise
    let sunsetUTC: Date?  = solar.sunset
    let isNight: Bool     = solar.isNighttime
}
```

---

## 9. `compactMenuTitle() -> String`

```swift
func compactMenuTitle() -> String
```

Used for the NSStatusItem primary line.

- If `store.shouldDisplay(.placeInMenubar)` is **false** (i.e. "show place name in menubar" is OFF): returns `dataObject.formattedTimezoneLabel()` immediately (label only).
- Otherwise builds a string:
  1. If `shouldShowDayInMenubar()`: appends `date(with: 0, displayType: .menu)` (short weekday).
  2. If `shouldShowDateInMenubar()`: appends `Date().formatter(with: "MMM d", timeZone: dataObject.timezone())`.
  3. Returns built string, or falls back to `formattedTimezoneLabel()` if both are empty.

**Note on the boolean polarity:** `shouldLabelBeShownAlongWithTime = !store.shouldDisplay(.placeInMenubar)`. The variable name is confusing — when `placeInMenubar` is `true` (show place), `shouldLabelBeShownAlongWithTime` is `false`, so it returns early with label only. This is a legacy inversion from the old codebase.

---

## 10. `compactMenuSubtitle() -> String`

```swift
func compactMenuSubtitle() -> String
```

Used for the NSStatusItem secondary line (shown when `placeInMenubar` is enabled).

- Builds day/date prefix identically to `compactMenuTitle` but gated on `store.shouldDisplay(.placeInMenubar)` == `true`.
- Always ends by appending `time(with: 0)` (the actual time string, `sliderValue = 0`).
- Returns: `"Thu Jun 13 3:45 PM"` or just `"3:45 PM"` depending on prefs.

---

## 11. Supporting Types

### `DateFormat` (namespace struct with static String constants)

```swift
public enum DateFormat {
    public static let twelveHour                    = "h:mm a"
    public static let twelveHourWithSeconds         = "h:mm:ss a"
    public static let twentyFourHour                = "HH:mm"
    public static let twentyFourHourWithSeconds     = "HH:mm:ss"
    public static let twelveHourWithZero            = "hh:mm a"
    public static let twelveHourWithZeroSeconds     = "hh:mm:ss a"
    public static let twelveHourWithoutSuffix       = "hh:mm"
    public static let twelveHourWithoutSuffixAndSeconds = "hh:mm:ss"
    public static let epochTime                     = "epoch"   // sentinel, not a DateFormatter format
}
```

### `TimezoneData.TimezoneOverride`

```swift
public enum TimezoneOverride: Int {
    case globalFormat               = 0
    case twelveHourFormat           = 1
    case twentyFourFormat           = 2
    case twelveHourWithSeconds      = 4
    case twentyHourWithSeconds      = 5
    case twelveHourPrecedingZero    = 7
    case twelveHourPrecedingZeroSeconds = 8
    case twelveHourWithoutSuffix    = 10
    case twelveHourWithoutSuffixAndSeconds = 11
    case epochTime                  = 12
}
```

### `timezoneFormat(_:) -> String` — per-row format resolution

```swift
public func timezoneFormat(_ currentFormat: NSNumber) -> String
// called as: dataObject.timezoneFormat(store.timezoneFormat())
```

If `overrideFormat == .globalFormat`, returns the global format from `TimezoneData.values[currentFormat]` (defaulting to `DateFormat.twelveHour`).
Otherwise returns the override-specific `DateFormat.*` constant.

### Global format index (`store.timezoneFormat() -> NSNumber`)

`DataStore.timezoneFormat()` reads `UserDefaultKeys.timeFormat` (`"timeFormat"`) from UserDefaults as an `Int`, returns as `NSNumber`. Maps via:

```swift
static let values: [NSNumber: String] = [
    0: "h:mm a",   // 12h
    1: "HH:mm",    // 24h
    3: "h:mm:ss a",
    4: "HH:mm:ss",
    6: "hh:mm a",
    7: "hh:mm:ss a",
    9: "hh:mm",
    10: "hh:mm:ss",
    11: "epoch"
]
```

---

## 12. `DateFormatterManager` — Static Factory (NOT thread-safe)

```swift
enum DateFormatterManager {
    static func dateFormatter(with style: DateFormatter.Style, for timezoneIdentifier: String) -> DateFormatter
    static func dateFormatterWithFormat(with style: DateFormatter.Style,
                                        format: String,
                                        timezoneIdentifier: String,
                                        locale: Locale = Locale(identifier: "en_US")) -> DateFormatter
    static func localizedFormatter(with format: String, for timezoneIdentifier: String,
                                   locale: Locale = Locale.autoupdatingCurrent) -> DateFormatter
    static func localizedSimpleFormatter(_ format: String) -> DateFormatter
}
```

**Critical gotcha:** All four methods return **shared mutable static `DateFormatter` instances** (one per slot). They are NOT thread-safe. Calling any of these from a background thread while another thread also calls it will corrupt the formatter. The existing code runs entirely on the main thread, so this is currently safe — a v4 rewrite that moves computation off-main MUST replace this with per-call `DateFormatter` instances or a pool.

---

## 13. `Date` Extension: `formatter(with:timeZone:locale:)`

```swift
// Defined at bottom of TimezoneDataOperations.swift
extension Date {
    func formatter(with format: String, timeZone: String, locale: Locale = Locale(identifier: "en-US")) -> String
}
// Example:
let dateStr = Date().formatter(with: "MMM d", timeZone: "America/New_York")
```

Uses `DateFormatterManager.dateFormatterWithFormat(with: .medium, format:..., timezoneIdentifier:..., locale:)`.

---

## 14. UserDefaults Keys Used by This Layer

| Key Constant | Raw String | Type | Meaning |
|---|---|---|---|
| `UserDefaultKeys.relativeDateKey` | `"relativeDate"` | `Int` → `RelativeDayDisplay.rawValue` | Panel date display mode |
| `UserDefaultKeys.showDayInMenubar` | `"showDayInMenubar"` | `Bool` | Show weekday in menubar |
| `UserDefaultKeys.showDateInMenubar` | `"showDateInMenubar"` | `Bool` | Show date in menubar |
| `UserDefaultKeys.showPlaceNameInMenubar` | `"showPlaceNameInMenubar"` | `Bool` | Show place name (drives title/subtitle split) |
| `UserDefaultKeys.timeFormat` | `"timeFormat"` | `Int` | Global time format index |
| `UserDefaultKeys.futureSliderRange` | `"sliderDayRange"` | `Int` | Max ±days for slider |
| `UserDefaultKeys.sunriseSunsetTime` | `"showSunriseSetTime"` | `Bool` | Whether sunrise/sunset row is shown |

---

## 15. Caches

Both caches are `private static` dictionaries on `TimezoneDataOperations` — shared across all instances:

```swift
private static var sunriseCache: [String: (Date?, Date?)] = [:]
// Key: "\(timezoneID)_\(startOfDay)"

private static var dstCache: [String: Date?] = [:]
// Key: "\(timezone)_\(startOfDay)"
```

Neither cache is ever invalidated except by key miss (new day). They are **never cleared on timezone list change** — if a user adds/removes a row mid-day the cache is still valid since the key includes the timezoneID.

---

## 16. Gotchas for v4 Rewrite

1. **`isSunriseOrSunset` naming is inverted:** `true` means nighttime (show sunrise next), `false` means daytime (show sunset next). The property name is misleading.

2. **`timeDifference()` ignores `sliderValue`:** Always computes relative to `Date()` (slider = 0). If you need offset-aware difference, you must compute it separately.

3. **Solar returns UTC `Date` objects.** Always apply a target timezone when displaying.

4. **`DateFormatterManager` is not thread-safe.** Do not call from background threads.

5. **`compactMenuTitle` boolean polarity is inverted.** `shouldLabelBeShownAlongWithTime = !store.shouldDisplay(.placeInMenubar)` means when the place-name-in-menubar setting is ON, the title returns the label only (early return). This is backwards from what the variable name implies.

6. **Epoch time format** (`"epoch"`) is a sentinel string, not a valid `DateFormatter` format. `time(with:)` special-cases it before creating a formatter.

7. **Sunrise cache is per calendar day but uses slider-adjusted date for the Solar calculation.** Scrubbing the slider into a different calendar day does NOT invalidate the sunrise cache — you get today's sunrise regardless of where the slider is pointed. This is intentional (the cache key uses `startOfDay(for: Date())`, not the slider-adjusted date).
