# Meridian — Antipattern Analysis Report

**Scope:** Full codebase, ~11K lines across 77 Swift files  
**Methodology:** Three parallel agents analyzed every non-dependency, non-generated Swift file against the [common antipatterns reference](https://github.com/alirezarezvani/claude-skills/blob/main/engineering-team/code-reviewer/references/common_antipatterns.md)  
**Status:** Analysis only — no remediation attempted

---

## Table of Contents

1. [Structural Antipatterns](#1-structural-antipatterns)
   - [1.1 God Classes](#11-god-classes)
   - [1.2 Long Methods](#12-long-methods)
   - [1.3 Deep Nesting](#13-deep-nesting)
   - [1.4 Magic Numbers and Strings](#14-magic-numbers-and-strings)
   - [1.5 Primitive Obsession](#15-primitive-obsession)
2. [Logic Antipatterns](#2-logic-antipatterns)
   - [2.1 Boolean Blindness](#21-boolean-blindness)
   - [2.2 Null Returns for Collections](#22-null-returns-for-collections)
   - [2.3 Stringly Typed Code](#23-stringly-typed-code)
3. [Security Antipatterns](#3-security-antipatterns)
   - [3.1 Hardcoded Credentials](#31-hardcoded-credentials)
   - [3.2 Unsafe Deserialization](#32-unsafe-deserialization)
   - [3.3 Missing Input Validation](#33-missing-input-validation)
4. [Performance Antipatterns](#4-performance-antipatterns)
   - [4.1 Unbounded Collections](#41-unbounded-collections)
   - [4.2 Synchronous / Expensive Work in Hot Paths](#42-synchronous--expensive-work-in-hot-paths)
   - [4.3 Unnecessary Recomputation](#43-unnecessary-recomputation)
5. [Testing Antipatterns](#5-testing-antipatterns)
   - [5.1 Test Code Duplication](#51-test-code-duplication)
   - [5.2 Testing Implementation Instead of Behavior](#52-testing-implementation-instead-of-behavior)
6. [Async Antipatterns](#6-async-antipatterns)
   - [6.1 Async Work at Launch / In Lifecycle Methods](#61-async-work-at-launch--in-lifecycle-methods)
   - [6.2 Floating / Unretained Tasks](#62-floating--unretained-tasks)
   - [6.3 Silent Error Swallowing](#63-silent-error-swallowing)

---

## 1. Structural Antipatterns

### 1.1 God Classes

Five classes carry responsibilities well beyond a single concern. The most severe cases are in the panel UI layer.

---

**`ParentPanelController`** — `Panel/ParentPanelController.swift` (567 lines) + `Panel/ParentPanelController+ModernSlider.swift` (206 lines) = **773 lines, 46 methods**

Unrelated concerns handled in a single class:
- Window/panel lifecycle and UI setup
- NSTableView data management and row height calculation
- Menubar display formatting
- Modern slider (collection view) including data source conformance
- Scroll view height calculations
- Popover management
- Clipboard operations
- URL opening (Report Issue, Rate, FAQs)
- Timezone deletion
- System timezone change handling
- Version status label updates

---

**`PanelController`** — `Panel/PanelController.swift` (503 lines, 29 methods)

Subclass of `ParentPanelController`. Together they total 1,270+ lines and 75 methods. Separate concerns within `PanelController` alone:
- Window positioning and frame calculation
- Floating mode / pin-to-desktop toggle
- Panel open/close animation
- Timer lifecycle (start/stop/pause)
- Drag handle UI setup
- Panel event logging
- NSWindowDelegate conformance
- Context menu handling
- Menubar timer coordination with AppDelegate

---

**`PreferencesViewController`** — `Preferences/General/PreferencesViewController.swift` (456 lines, 37 methods)

- Timezone list table view management
- Search results table view management
- Sorting (3 sort actions)
- Alert presentation for menubar warnings
- Favourite/unfavourite logic
- Status bar appearance updates
- Accessibility setup
- Shortcut recorder setup
- Empty-state management
- NSTableViewDataSource/Delegate conformance
- PreferenceSelectionUpdates protocol (6 delegate methods)

---

**`TimezoneAdditionHandler`** — `Preferences/General/TimezoneAdditionHandler.swift` (453 lines, 21 methods)

- Geocoding search orchestration (networking)
- Timezone installation and persistence
- UI state management (progress indicators, placeholders, button enable/disable)
- Search field filtering
- Table view selection management

---

**`TimezoneDataOperations`** — `Panel/Data Layer/TimezoneDataOperations.swift` (447 lines, 20 methods)

- Time formatting
- Date formatting (multiple formats)
- DST transition detection
- Menubar title construction (compact + standard modes)
- Sunrise/sunset computation via Solar
- Time difference calculation
- Locale-aware date string generation
- Object persistence (`saveObject`)

---

**`AppearanceViewController`** — `Preferences/Appearance/AppearanceViewController.swift` (391 lines, 23 methods)

Each `@IBAction` handles a completely independent preference domain: time format, theme, slider range, menubar mode, app display options, float-on-top, day/date/place display toggles, panel preview table view, font size.

---

### 1.2 Long Methods

Methods exceeding 50 lines or containing density that matches the "requires scrolling to read" threshold:

| Method | File | Lines |
|--------|------|-------|
| `PanelController.open()` | `Panel/PanelController.swift:154` | 62 |
| `TimezoneDataOperations.date(with:displayType:)` | `Panel/Data Layer/TimezoneDataOperations.swift:215` | 60 |
| `TimezoneDataOperations.menuTitle()` | `Panel/Data Layer/TimezoneDataOperations.swift:133` | 57 |
| `TimezoneAdditionHandler.search()` | `Preferences/General/TimezoneAdditionHandler.swift:51` | 63 |
| `ParentPanelController.updateTime()` | `Panel/ParentPanelController.swift:456` | 50 |
| `PanelController.log()` | `Panel/PanelController.swift:260` | 45 |
| `TimezoneAdditionHandler.cleanupAfterInstallingTimezone()` | `Preferences/General/TimezoneAdditionHandler.swift:342` | 46 |
| `PreferencesViewController.showAlertIfMoreThanOneTimezoneHasBeenAddedToTheMenubar()` | `Preferences/General/PreferencesViewController.swift:256` | 46 |
| `TimezoneDataSource.tableView(_:viewFor:row:)` | `Panel/UI/TimezoneDataSource.swift:42` | 48 |
| `TimezoneDataSource.tableView(_:heightOfRow:)` | `Panel/UI/TimezoneDataSource.swift:91` | 37 (dense logic) |
| `PanelController.setPanelFrame()` | `Panel/PanelController.swift:219` | 40 |
| `ParentPanelController.setScrollViewConstraint()` | `Panel/ParentPanelController.swift:290` | 41 |
| `ParentPanelController+ModernSlider.setupModernSliderIfNeccessary()` | `Panel/ParentPanelController+ModernSlider.swift:24` | 40 |

---

### 1.3 Deep Nesting

Indentation exceeding 4 levels (class > extension > func counts as 2):

| Location | File | Depth | Description |
|----------|------|-------|-------------|
| `AppDelegate.backfillMissingCoordinates()` line 109 | `AppDelegate.swift` | **6** | class > func > Task closure > for loop > `if let placemark` > `if let encoded` — deepest in codebase |
| `TimezoneAdditionHandler.search()` lines 73–113 | `Preferences/General/TimezoneAdditionHandler.swift` | 5 | func > Task closure > do/catch > guard/if |
| `TimezoneAdditionHandler.getTimezone(for:and:)` lines 166–194 | `Preferences/General/TimezoneAdditionHandler.swift` | 5 | Same pattern |
| `TimezoneAdditionHandler.cleanupAfterInstallingCity()` lines 301–339 | `Preferences/General/TimezoneAdditionHandler.swift` | 5 | Nested if/guard inside func |
| `TimezoneDataOperations.date(with:displayType:)` lines 230–251 | `Panel/Data Layer/TimezoneDataOperations.swift` | 5 | func > if displayType > if relativeDayPreference > guard/if |
| `TimezoneDataOperations.menuTitle()` lines 143–155 | `Panel/Data Layer/TimezoneDataOperations.swift` | 5 | func > if shouldCityBeShown > if let address > if let label |
| `TimezoneCellView.updateRelativeDateVisibility()` lines 77–97 | `Panel/UI/TimezoneCellView.swift` | 5 | func > if hasContent > for constraint > if constraint.identifier |
| `TimezoneCellView.updateTimeTopSpace()` lines 100–118 | `Panel/UI/TimezoneCellView.swift` | 5 | func > for constraint > if hasRelativeDate > if sunriseVisible |
| `ParentPanelController.awakeFromNib()` lines 125–137 | `Panel/ParentPanelController.swift` | 5 | func > if-else chain > if value.intValue > if modernContainerView |
| `ParentPanelController.setScrollViewConstraint()` lines 318–329 | `Panel/ParentPanelController.swift` | 5 | func > if shouldDisplay > if isModernSlider > if scrollViewHeight |
| `ParentPanelController.updateTime()` lines 471–504 | `Panel/ParentPanelController.swift` | 5 | func > stride.forEach > if cellView > if modernContainerView |
| `PreferencesViewController.showAlertIfMoreThanOne...()` lines 288–299 | `Preferences/General/PreferencesViewController.swift` | 5 | func > if response.rawValue > OperationQueue closure > if suppressionButton |
| `TimezoneDataSource.tableView(_:rowActionsForRow:edge:)` lines 134–155 | `Panel/UI/TimezoneDataSource.swift` | 5 | func > if edge > handler closure > if isSystemTimezone |
| `SearchDataSource.setupTimezoneDatasource()` lines 104–127 | `Preferences/General/SearchDataSource.swift` | 5 | func > for identifier > if let timezoneObject > if let tagsPresent |

---

### 1.4 Magic Numbers and Strings

**Selected magic numbers (non-exhaustive — over 60 instances found):**

| File | Line(s) | Value(s) | Context |
|------|---------|---------|---------|
| `Panel/ParentPanelController.swift` | 10–11 | `96`, `15` | Slider points per day, minutes per point |
| `Panel/ParentPanelController.swift` | 252, 266, 279, 283 | `68.0`, `88.0`, `8.0`, `5` | Row height thresholds |
| `Panel/ParentPanelController.swift` | 314–326 | `100`, `200`, `300` | Screen height offsets for scroll view sizing |
| `Panel/ParentPanelController.swift` | 335–336 | `13.0`, `0.1` | Menubar font size and baseline offset — **duplicated** in `StatusItemHandler.swift:23–24` |
| `Panel/PanelController.swift` | 85, 88, 103–105, 109 | `6`, `16`, `8`, `22`, `34` | Drag handle / pin button layout constants |
| `Panel/PanelController.swift` | 376 | `0.1` | Animation duration |
| `Panel/Data Layer/TimezoneDataOperations.swift` | 10 | `8` | DST lookahead days |
| `Panel/Data Layer/TimezoneDataOperations.swift` | 34 | `3600` | Seconds per hour in epoch offset calculation |
| `Panel/Data Layer/TimezoneDataOperations.swift` | 220–254 | `3`, `2` | `relativeDayPreference` sentinel values for "hide" and "date" |
| `Preferences/General/TimezoneAdditionHandler.swift` | 263, 416, 428, 436 | `100`, `50`, `0.5`, `6` | Max timezone count, max search chars, debounce, scroll threshold |
| `Panel/UI/TimezoneDataSource.swift` | 100, 102, 104, 109, 113 | `100`, `60`, `65`, `5`, `8`, `15` | Row height values — **duplicated** in `AppearanceViewController.swift:381` |
| `Panel/UI/TimezoneDataSource.swift` | 171 | `1000` | `NSAlert` response raw value — **duplicated** in `PreferencesViewController.swift:288` |
| `Preferences/Menu Bar/StatusItemHandler.swift` | 15–18 | `55`, `12`, `20` | Buffer width constants — **duplicated** in `StatusContainerView.swift:8–20` |
| `Preferences/Menu Bar/StatusContainerView.swift` | 63–64 | `0.92` | Line height multiple — **duplicated** in `StatusItemView.swift:7` |
| `CoreModelKit/.../TimezoneData.swift` | 59–73 | `0,3,4,6,7,9,10,11` | Non-contiguous `[NSNumber: String]` format index keys |
| `Overall App/AppDefaults.swift` | 30, 32, 33 | `4`, `6`, `30` | Default font size, slider range, truncate length |

**Repeated magic strings:**

| String | Count | Files |
|--------|-------|-------|
| `"Error"` as nil-coalescing fallback | 8+ | `TimezoneData.swift`, `TimezoneAdditionHandler.swift`, `StatusItemView.swift`, `TimezoneDataOperations.swift` |
| `"Avenir-Light"` | 5+ | `PreferencesViewController.swift:181`, `AboutView.swift:22,37,47,74,199`, `Toasty.swift:81` |
| `"MMM d"` date format | 3 | `TimezoneDataOperations.swift:93,96,174` |
| `"en-US"` / `"en_US"` locale string | 5+ | `TimezoneDataOperations.swift`, `DateFormatterManager.swift`, `StatusItemView.swift` |
| `"Time Scroller"` | 3 | `PanelController.swift:188`, `ParentPanelController+ModernSlider.swift:95,175` |
| `"latitude"` / `"longitude"` as dict keys | 4+ | `TimezoneAdditionHandler.swift:214–215,319–320`, `TimezoneSearchService.swift:47–48` |
| `"formattedAddress"`, `"customLabel"`, `"place_id"`, `"timezoneID"` | 3 each | Defined in `Strings.swift` but also hard-coded separately in `ModelConstants` and `PreferencesDataSourceConstants` |

---

### 1.5 Primitive Obsession

**`[String: Any]` dictionary as timezone data carrier**

The `TimezoneData.init(with dictionary: [String: Any])` constructor accepts a loosely-typed dictionary. The same six-key structure (`latitude`, `longitude`, `formattedAddress`, `customLabel`, `timezoneID`, `place_id`) is constructed independently in at least five places:

- `TimezoneAdditionHandler.swift:90–97` (`totalPackage` dictionary)
- `TimezoneAdditionHandler.swift:210–218` (`newTimeZone` dictionary)
- `TimezoneAdditionHandler.swift:314–323` (duplicate `newTimeZone` dictionary)
- `TimezoneSearchService.swift:45–52` (`totalPackage` dictionary)
- `AppearanceViewController.swift:47–54` (preview timezone dictionary)

These six primitives always travel together and share identical keys.

---

**`TimezoneDataOperations.formatOffset(prefix:agoText:deSuffix:local:timezoneDate:)`** — `Panel/Data Layer/TimezoneDataOperations.swift`

Five parameters, three of which (`prefix: String`, `agoText: String`, `deSuffix: String`) are formatting primitives representing a single offset display configuration that always travel as a group.

---

**NSNumber-as-enum for preferences** — `Overall App/DataStore.swift:123–144`

The `shouldDisplay(_ type:)` method compares `NSNumber` values against magic integers (`0`, `1`) to determine booleans. Different keys use inverted conventions (0 = "yes" for some, 0 = "no" for others) with no compile-time safety across 28+ call sites.

---

**NSAlert response as raw integer** — 2 locations

`PreferencesViewController.swift:288` and `TimezoneDataSource.swift:171` both check `response.rawValue == 1000` instead of using `NSApplication.ModalResponse.alertFirstButtonReturn`.

---

**Row height calculation primitives** — 2 independent parallel implementations

`ParentPanelController.getAdjustedRowHeight` (lines 246–288) and `TimezoneDataSource.tableView(_:heightOfRow:)` (lines 91–127) both independently compute row heights from the same unstructured set: userFontSize, shouldShowSunrise, note presence, isSystemTimezone, DST availability.

---

## 2. Logic Antipatterns

### 2.1 Boolean Blindness

**No significant instances found.** Boolean parameters in this codebase are generally passed individually. The `refreshTimezoneTableView(_ shouldSelectNewlyInsertedTimezone: Bool)` call in `PreferencesViewController.swift:100` passes a single boolean whose purpose is moderately clear from context.

---

### 2.2 Null Returns for Collections

**`DataStore.menubarTimezones()`** — `Overall App/DataStore.swift:22` (protocol) and `:71` (implementation)

Return type is `[Data]?` but the implementation always returns a non-nil `[Data]`. Every call site compensates: `store.menubarTimezones()?.count ?? 0`, `store.menubarTimezones()?.isEmpty ?? true`, etc.

---

**`MenubarTitleProvider.titleForMenubar()`** — `Preferences/Menu Bar/MenubarTitleProvider.swift:14`

Returns `String?` and returns `nil` in multiple branches where an empty string would be semantically equivalent. Both callers in `StatusItemHandler.swift:283` and `:348` unconditionally coalesce with `?? ""`.

---

### 2.3 Stringly Typed Code

This is the most pervasive logic antipattern in the codebase — found in 11 distinct locations.

---

**Error classification by localized string** — `Preferences/General/TimezoneAdditionHandler.swift:186`

```swift
if error.localizedDescription == "The Internet connection appears to be offline."
```
Error type is detected by matching a localized string rather than by inspecting `error.code` or `error.domain`. A related string constant exists in `PreferencesViewController.swift:17` (`PreferencesConstants.offlineErrorMessage`) and is matched at line 122.

---

**Special timezone detection by display name** — `Preferences/General/TimezoneAdditionHandler.swift:445–447`

```swift
if selection.formattedName == "Anywhere on Earth" {
} else if selection.formattedName == "UTC" {
```
No type-level distinction exists for these special timezones; logic branches on display strings.

---

**Table column logic via string identifier** — 3 locations

- `Preferences/General/TimezoneSortingManager.swift:62`: `if identifier == "formattedAddress"`
- `Preferences/General/PreferencesDataSource.swift:115–123`: Three consecutive comparisons against `.rawValue` for `timezoneNameIdentifier`, `customLabelIdentifier`, `favoriteTimezoneIdentifier`
- `Preferences/General/PreferencesViewController.swift:443`: `if tableColumn.identifier.rawValue == "favouriteTimezone"`

---

**Constraint identification by string** — `Panel/UI/TimezoneCellView.swift:70,82,85,92,103,161`

Six separate locations use `constraint.identifier == "..."` to locate and modify specific Auto Layout constraints. Strings used: `"width"`, `"custom-name-top-space"`, `"time-top-space"`, `"height"`.

---

**Locale detection by substring** — 4 locations

- `Panel/Data Layer/TimezoneDataOperations.swift:331–332`: `if !currentLocale.contains("en")` / `if currentLocale.contains("de")`
- `Preferences/Menu Bar/StatusContainerView.swift:63`: `userPreferredLanguage.contains("en") ? 0.92 : 1`
- `Preferences/Menu Bar/StatusItemView.swift:19,53`: Same `contains("en")` pattern repeated twice

---

**`relativeDayPreference` as magic integer** — `Panel/Data Layer/TimezoneDataOperations.swift:220–261`

`date(with:displayType:)` branches on `relativeDayPreference.intValue` being `0`, `1`, `2`, or `3` using raw integer comparisons. The integers map to display modes (relative, actual day, date, hidden) but no enum exists.

---

**`[NSNumber: String]` dictionary for date formats** — `CoreModelKit/.../TimezoneData.swift:58–74`

`TimezoneData.values` maps integer keys to format strings with non-contiguous indices (`0,1,3,4,6,7,9,10,11` — gaps at `2`, `5`, `8` exist because the popup menu has disabled separator rows). No compile-time safety.

---

**Seconds detection by format string content** — 2 locations

- `CoreModelKit/.../TimezoneData.swift:266,272`: `formatInString.contains("ss")`
- `Preferences/Appearance/AppearanceViewController.swift:178`: `selectedFormat.contains("ss")`

---

**UserDefaults keys as untyped stringly-typed configuration**

`Overall App/Strings.swift:5–34` defines 28+ plain `String` constants. `DataStore.retrieve(key: String) -> Any?` returns untyped `Any?`, requiring callers to cast to `NSNumber` / `Int` / `String` at every one of the 28+ call sites.

---

## 3. Security Antipatterns

### 3.1 Hardcoded Credentials

**No instances found.** The codebase contains no hardcoded passwords, API keys, tokens, or secrets. The app uses Apple's CLGeocoder (no API key required) and Sparkle (no credentials in source).

---

### 3.2 Unsafe Deserialization

**No instances found.** All archiving uses the `secureArchive(with:)` wrapper in `Overall App/Foundation + Additions.swift:29`, which calls `NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding: true)`. The unarchiving path in `CoreModelKit/.../TimezoneData.swift:139–142` sets `unarchiver.requiresSecureCoding = true` and uses `decodeObject(of: TimezoneData.self, ...)`. `TimezoneData` conforms to `NSSecureCoding`. The `NSKeyedUnarchiver.unarchivedObject(ofClass:from:)` call in `PreferencesDataSource.swift:69` uses the type-safe API.

---

### 3.3 Missing Input Validation

**Partial validation on search input** — `Preferences/General/TimezoneAdditionHandler.swift:416`

A length check exists (max 50 chars), but the search string is not sanitized for control characters or null bytes before being passed to `NetworkManager.geocodeAddress()` at line 75 and `TimezoneSearchService.searchLocalTimezones()` at line 117.

---

**Custom label — whitespace-trim only** — `Preferences/General/PreferencesDataSource.swift:164`

```swift
let formattedValue = label.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
```
User-edited timezone labels are only whitespace-trimmed. No length limit, no character restriction. The label is stored directly in `TimezoneData.customLabel` and displayed in the menubar and panel.

---

**`TimezoneData.init(with:)` — no range/validity checks** — `CoreModelKit/.../TimezoneData.swift:101–113`

The dictionary initializer extracts `latitude`/`longitude` with `as?` casts and falls back to `"Error"` strings for missing values. There is no validation that `timezoneID` is a valid identifier or that coordinates are within valid ranges (±90 lat, ±180 lon). Called from four production sites with geocoder results.

---

**Drag-and-drop pasteboard uses generic UTI** — `Preferences/General/PreferencesDataSource.swift:44–48`

Row index data is serialized to the pasteboard with type `"public.text"` — a generic UTI — rather than a private app-specific type. Any application could theoretically place data on the pasteboard under this type. The `NSIndexSet` unarchiving provides type-level protection on read.

---

**Silent `TimezoneData()` default on nil data** — `CoreModelKit/.../TimezoneData.swift:134–136`

When `customObject(from:)` receives `nil`, it returns a default-constructed `TimezoneData()` (no timezone ID, no coordinates) rather than `nil`. Callers such as `ParentPanelController.swift:393` force-unwrap the non-nil result and receive a blank, potentially invalid object that can propagate silently.

---

## 4. Performance Antipatterns

### 4.1 Unbounded Collections

**Full NSKeyedUnarchiver deserialization on every access**

There is no cap or pagination on the timezone list. Multiple hot-path call sites deserialize the entire `[Data]` array into `[TimezoneData]` objects on every invocation:

- `Panel/ParentPanelController.swift:179–187` (`updateHomeObject`): Deserializes and re-serializes all timezones on system timezone change.
- `Panel/ParentPanelController.swift:392–393` (`updateDefaultPreferences`): Force-unwrapping deserialization of every timezone on every panel open — `defaults.map { TimezoneData.customObject(from: $0)! }`.
- `Panel/ParentPanelController.swift:294–297` (`setScrollViewConstraint`): Iterates every preference with `TimezoneData.customObject(from:)` to compute total scroll view height.
- `Overall App/LocationController.swift:57–66` (`updateHomeObject`): Same pattern — deserializes all, iterates all, re-serializes all, writes all back.
- `Overall App/DataStore.swift:50–53` (init) and `:65–68` (`setTimezones`): Every call to `setTimezones` re-filters the entire collection to rebuild `cachedMenubarTimezones`.

---

**`shouldDisplaySecondsInMenubar` deserializes all menubar timezones twice per refresh**

`Preferences/Menu Bar/StatusItemHandler.swift:233–244`: Deserializes every menubar timezone to check for seconds display. Called from both `calculateFireDate()` (line 247) and `updateMenubar()` (line 211) — two full deserialization passes per menubar update cycle.

---

### 4.2 Synchronous / Expensive Work in Hot Paths

The 1-second `Repeater` timer calls `updateTime()` in `Panel/ParentPanelController.swift:456–504`. The following expensive operations run inside this callback on every tick:

---

**`UserDefaults` reads per timezone per second** — `Panel/ParentPanelController.swift:487`

`TimezoneDataOperations.date(with:displayType:)` calls `store.retrieve(key: UserDefaultKeys.relativeDateKey)` at `Panel/Data Layer/TimezoneDataOperations.swift:216` — a synchronous plist read — for every visible timezone on every 1-second tick.

---

**`DataStore.shouldDisplay` reads from `UserDefaults` in table callbacks**

- `Panel/UI/TimezoneDataSource.swift:96–100` (`tableView(_:heightOfRow:)`): Calls `dataStore.retrieve(key:)` and `dataStore.shouldDisplay(.sunrise)` for every row during every reload triggered by the timer.
- `Panel/UI/TimezoneCellView.swift:132` (`setupTextSize`): Calls `DataStore.shared().retrieve(key: UserDefaultKeys.userFontSizePreference)` on every cell layout pass.

---

**Solar trigonometric calculations per timezone per second** — `Panel/ParentPanelController.swift:483`

`dataOperation.formattedSunriseTime(with:)` triggers `initializeSunriseSunset` at `Panel/Data Layer/TimezoneDataOperations.swift:346–371` on every tick for every timezone with coordinates. Sunrise/sunset values change at most once per day.

---

**DST transition computed per cell per second** — `Panel/ParentPanelController.swift:497`

`nextDaylightSavingsTransitionIfAvailable` is called per timezone per second. DST transitions change at most twice per year. Also called in `TimezoneDataSource.tableView(_:viewFor:)` and `tableView(_:heightOfRow:)`.

---

**New `TimezoneDataOperations` allocated per row per second** — `Panel/ParentPanelController.swift:481`

`let dataOperation = TimezoneDataOperations(with: model, store: dataStore)` — a new instance is allocated for every visible row on every 1-second tick, along with all associated `DateFormatter` calls.

---

### 4.3 Unnecessary Recomputation

**New `DateFormatter` in `formattedSunriseTime`** — `Panel/Data Layer/TimezoneDataOperations.swift:395–399`

`let dateFormatter = DateFormatter()` is allocated on every call, bypassing the `DateFormatterManager` cache used everywhere else. Called per timezone per second (see §4.2 above). `DateFormatter` allocation is expensive.

---

**New `DateFormatter` in `updateVersionStatusLabel`** — `Panel/ParentPanelController.swift:161–162`

Allocated each time the version label is updated.

---

**New `DateFormatter` in `AboutView.lastCheckedText`** — `Preferences/About/AboutView.swift:165`

Allocated on every SwiftUI body evaluation.

---

**Unused `dateFormatter` instance property** — `Panel/ParentPanelController.swift:17`

`var dateFormatter = DateFormatter()` is allocated at construction time but never referenced anywhere in the class.

---

**`operationsObject` as computed property** — `Preferences/Menu Bar/StatusItemView.swift:44–46`

```swift
private var operationsObject: TimezoneDataOperations {
    return TimezoneDataOperations(with: dataObject, store: DataStore.shared())
}
```
A new `TimezoneDataOperations` is created on every property access. Called twice from `initialSetup()` and twice from `statusItemViewSetNeedsDisplay()` — 4 allocations per menubar refresh per compact-mode timezone.

---

**Global paragraph style and font as computed properties** — `Preferences/Menu Bar/StatusItemView.swift:6–24`

`defaultTimeParagraphStyle`, `defaultParagraphStyle`, and `compactModeTimeFont` are all `var` computed properties that construct new `NSMutableParagraphStyle` / call `NSFont.monospacedDigitSystemFont` on every access. Similarly `timeAttributes` and `textFontAttributes` (lines 58–80) are computed properties creating new dictionaries each access.

---

**`StatusContainerView.bestWidth` recomputes string measurements on every menubar refresh** — `Preferences/Menu Bar/StatusContainerView.swift:142–161`

Called from `adjustWidthIfNeccessary()` at lines 178–195. Creates a new `TimezoneDataOperations`, calls `compactMenuSubtitle()` and `compactMenuTitle()`, and performs two `NSFont.size(for:)` string measurements per timezone per menubar refresh.

---

**Redundant table cell configuration** — `Panel/UI/TimezoneDataSource.swift:59`

In `tableView(_:viewFor:)`, a full `TimezoneDataOperations` is created and used to configure sunrise, date, time, and DST info. The same cell is reconfigured completely one second later by `updateTime()`. The initial setup at table-load is immediately overwritten.

---

**Double string size calculation** — `Panel/UI/TimezoneCellView.swift:155–158`

Two separate `.size(withAttributes:)` calls on the same `NSString` (one for height, one for width), where a single call returning `CGSize` would suffice. Called on every cell layout pass.

---

## 5. Testing Antipatterns

### 5.1 Test Code Duplication

**Timezone fixture dictionaries defined independently in 5 files**

| File | Fixtures |
|------|---------|
| `MeridianUnitTests/TimezoneDataOperationsTests.swift:11–41` | `newYork`, `tokyo`, `london`, `noCoords` |
| `MeridianUnitTests/MenubarTitleProviderTests.swift:11–25` | `mumbai`, `newYork` |
| `MeridianUnitTests/StandardMenubarHandlerTests.swift:9–15` | `mumbai` |
| `MeridianUnitTests/MeridianUnitTests.swift:20–64` | `california`, `mumbai`, `auckland`, `florida`, `onlyTimezone`, `omaha` |
| `MeridianUnitTests/TimezoneSortingManagerTests.swift:16–55` | `sanFrancisco`, `newYork`, `london`, `tokyo` |

These share the same key structure but are independently maintained. A schema change to `TimezoneData`'s dictionary format requires updating all five files.

---

**Duplicated `MockDataStore` setup**

- `MeridianUnitTests/TimezoneDataOperationsTests.swift:43–50` (`setUp`): Creates `MockDataStore`, sets format and relative date preferences.
- `MeridianUnitTests/MenubarTitleProviderTests.swift:27–38` (`setUp`): Creates `MockDataStore`, sets same preferences plus `menubarCompactMode`.

Essentially the same pattern with minor variations.

---

**`saveObject` helper duplicated in `StandardMenubarHandlerTests`**

`MeridianUnitTests/StandardMenubarHandlerTests.swift:24–34`: Manually archives and appends to the store. Duplicates the logic of both `TimezoneDataOperations.saveObject()` and `MockDataStore.addTimezone()`. Used across 5 test methods within the same file.

---

**`makeMockStore` pattern duplicated**

- `MeridianUnitTests/StandardMenubarHandlerTests.swift:17–22`: Creates `UserDefaults(suiteName:)` and `DataStore`
- `MeridianUnitTests/LocationControllerTests.swift:14–19` (`setUp`): Same pattern, different suite name

---

### 5.2 Testing Implementation Instead of Behavior

**Tests using real `UserDefaults.standard` and `DataStore.shared()` singleton**

`MeridianUnitTests/MeridianUnitTests.swift:67`: `DataStore.shared()` is used directly throughout the test class, coupling tests to global mutable state. Lines 86–103, 106–119, and 157–174 all modify real `UserDefaults.standard` and the shared singleton.

---

**`AppDelegateTests` operates on the live application singleton**

`MeridianUnitTests/AppDelegateTests.swift:9–15,29–31`: Tests operate against `NSApplication.shared.delegate as? AppDelegate`, including real status bar items and real `UserDefaults`. Line 65 reads `UserDefaults.standard.integer(forKey:)` and line 73 calls `hideFromDock()`, which mutates actual global activation policy state.

---

**Tests inspecting NSStatusItem internal UI properties**

`MeridianUnitTests/AppDelegateTests.swift:78–85` (`testMenubarInvalidationToIcon`): Asserts against `statusItem.button?.subviews`, `.title`, `.image`, `.imagePosition`, `.toolTip` — implementation-level rendering details rather than behavioral outcomes.

---

**`testDecoding` tests an internal nil-data defensive fallback**

`MeridianUnitTests/MeridianUnitTests.swift:122–129`: Tests that `TimezoneData.customObject(from: nil)` returns a default `TimezoneData()`. This exercises an internal deserialization edge case rather than any user-visible behavior.

---

**`testDeserializationWithInvalidSelectionType` tampers with internal archive format**

`MeridianUnitTests/MeridianUnitTests.swift:462–503`: Manually modifies the plist structure of `NSKeyedArchiver` output to inject an invalid `selectionType` raw value. Tests internal `NSCoding` behavior of `TimezoneData` under corrupt data, not public behavior.

---

## 6. Async Antipatterns

### 6.1 Async Work at Launch / In Lifecycle Methods

**Fire-and-forget geocoding Task in `applicationDidFinishLaunching`** — `AppDelegate.swift:85–116`

`backfillMissingCoordinates()` launches `Task { @MainActor in ... }` (line 100) that performs geocoding in a loop. The Task is not stored, cannot be cancelled on app termination, and uses `try?` to silently swallow all geocoding failures.

---

**Synchronous file I/O on main thread during launch** — `AppDelegate.swift:18–19`

`checkForPreviousUncleanExit()` and `writeSentinelFile()` perform synchronous `FileManager` operations (`fileExists`, `String(contentsOf:)`, `createDirectory`, `write(to:)`) on the main thread during `applicationDidFinishLaunching`.

---

### 6.2 Floating / Unretained Tasks

Three async Tasks are launched without storing a reference, making them impossible to cancel:

| Location | Task | Cancellable? |
|----------|------|-------------|
| `AppDelegate.swift:100` | Coordinate backfill geocoding loop | No |
| `Preferences/General/TimezoneAdditionHandler.swift:166–195` (`getTimezone`) | Geocode after timezone selection | No |
| `Preferences/General/TimezoneAdditionHandler.swift:358–387` (`cleanupAfterInstallingTimezone`) | Geocode after installation | No |

By contrast, `searchTask` at `TimezoneAdditionHandler.swift:29` is the **one Task that is properly managed** — stored as a property, cancelled before new searches, correctly lifecycle-managed.

---

### 6.3 Silent Error Swallowing

`try?` used in production code to discard errors entirely — no logging, no user feedback, no fallback behavior:

| File | Line | Operation Silenced |
|------|------|--------------------|
| `AppDelegate.swift` | 51 | `FileManager.createDirectory` — sentinel directory creation |
| `AppDelegate.swift` | 53 | `String.write(to:)` — sentinel file write |
| `AppDelegate.swift` | 58 | `FileManager.removeItem` — sentinel file cleanup |
| `AppDelegate.swift` | 105 | `NetworkManager.geocodeAddress` — coordinate backfill |
| `Preferences/General/TimezoneAdditionHandler.swift` | 362 | `NetworkManager.geocodeAddress` — post-install geocoding |
| `Overall App/GlobalShortcutMonitor.swift` | 71 | `JSONDecoder.decode` — shortcut load on launch |
| `Overall App/GlobalShortcutMonitor.swift` | 82, 95 | `JSONEncoder.encode` — shortcut save (change would be silently lost) |
| `Overall App/Foundation + Additions.swift` | 30 | `NSKeyedArchiver.archivedData` — timezone serialization |
| `CoreModelKit/.../TimezoneData.swift` | 139 | `NSKeyedUnarchiver(forReadingFrom:)` — timezone deserialization |

The `GlobalShortcutMonitor` case at lines 82 and 95 is particularly notable: if JSON encoding fails, the user's custom shortcut change is silently discarded with no indication that anything went wrong.

---

## Summary

| Category | Severity | Instance Count |
|----------|----------|----------------|
| God Classes | High | 6 classes |
| Long Methods | Medium | 13 methods |
| Deep Nesting | Medium | 14 locations |
| Magic Numbers/Strings | Medium | 60+ instances |
| Primitive Obsession | Medium | 5 patterns |
| Null Returns for Collections | Low | 2 |
| Stringly Typed Code | Medium | 11 locations |
| Missing Input Validation | Low–Medium | 5 locations |
| Unbounded Collections + Hot Deserialization | High | 5 hot paths |
| Expensive Work in 1s Timer | High | 5 per-tick operations |
| Unnecessary Recomputation | Medium | 10 instances |
| Test Code Duplication | Low | 4 patterns |
| Testing Implementation Details | Low | 5 tests |
| Floating Tasks | Medium | 3 unretained Tasks |
| Silent `try?` | Medium | 9 sites |

**Highest-severity findings** (performance impact on every 1-second timer tick):
1. Solar calculations (`initializeSunriseSunset`) run per timezone per second
2. `nextDaylightSavingsTransitionIfAvailable` computed per timezone per second
3. New `TimezoneDataOperations` + `DateFormatter` allocated per row per second
4. Uncached `UserDefaults` reads inside the timer callback
5. `operationsObject` computed property allocating a new object on every menubar refresh
