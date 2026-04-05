# Meridian Codebase Antipattern Report — v2

**Date:** 2026-04-05
**Codebase version:** v2.17.0
**Analysis basis:** [common_antipatterns.md](https://github.com/alirezarezvani/claude-skills/blob/main/engineering-team/code-reviewer/references/common_antipatterns.md)

> v2 reflects the state of the codebase after the round 1 and round 2 housekeeping fixes merged in PR #71. Previous findings that were remediated are not repeated here. This report covers only open findings.

---

## Table of Contents

- [Structural Antipatterns](#structural-antipatterns)
- [Logic Antipatterns](#logic-antipatterns)
- [Security Antipatterns](#security-antipatterns)
- [Performance Antipatterns](#performance-antipatterns)
- [Testing Antipatterns](#testing-antipatterns)
- [Async Antipatterns](#async-antipatterns)
- [Summary](#summary)

---

## Structural Antipatterns

### God Class

Three classes handle too many unrelated concerns.

**`ParentPanelController`** — `Panel/ParentPanelController.swift`
- 31 properties and 18+ methods spanning: data source management, timer management, slider operations, popover management, table updates, menubar updates, user interaction, and panel color management.
- Severity: **High**

**`TimezoneAdditionHandler`** — `Preferences/General/TimezoneAdditionHandler.swift`
- 450+ lines, 20+ methods handling timezone search, addition, geocoding, UI state management, and error handling simultaneously.
- Severity: **High**

**`PreferencesViewController`** — `Preferences/General/PreferencesViewController.swift`
- 456 lines, 20+ methods handling table management, sorting, favorites, data refresh, and keyboard shortcuts.
- Severity: **High**

**`AppearanceViewController`** — `Preferences/Appearance/AppearanceViewController.swift`
- 407 lines, 15+ methods managing time format, theme, sliders, preview, and menubar display settings across multiple concerns.
- Severity: **Medium**

---

### Long Method

**`TimezoneAdditionHandler.search()`** — `Preferences/General/TimezoneAdditionHandler.swift:63–125`
- 63 lines with async task handling, error handling, and UI state management inside a single method.
- Severity: **Medium**

**`TimezoneAdditionHandler.cleanupAfterInstallingTimezone()`** — `Preferences/General/TimezoneAdditionHandler.swift:356–418`
- 63 lines with nested async/geocoding logic and multiple UI cleanup paths.
- Severity: **Medium**

**`TimezoneDataOperations.date()`** — `Panel/Data Layer/TimezoneDataOperations.swift:235–293`
- 59 lines with multiple nested if/else branches for date formatting; 4 levels of nesting with weekday comparison logic at lines 262–273.
- Severity: **Medium**

**`PanelController.log()`** — `Panel/PanelController.swift:273–317`
- 45 lines; single massive guard with 9 conditions (lines 278–290) retrieving 8+ UserDefaults keys sequentially.
- Severity: **Medium**

**`ParentPanelController.getAdjustedRowHeight()`** — `Panel/ParentPanelController.swift:227–269`
- 43 lines with complex nested conditionals for row height calculation; 4 levels of nesting.
- Severity: **Medium**

**`ParentPanelController.setScrollViewConstraint()`** — `Panel/ParentPanelController.swift:271–310`
- 40 lines mixing loop logic, conditional calculations, and constraint updates.
- Severity: **Medium**

---

### Deep Nesting

**`TimezoneCellView.updateTimeTopSpace()`** — `Panel/UI/TimezoneCellView.swift:106–121`
- Switch statement with pattern matching and nested `if` conditions reaching 5 levels deep.
- Severity: **Medium**

**`PanelController.setPanelFrame()`** — `Panel/PanelController.swift:232–271`
- 4-level nesting with nested `guard` and screen iteration logic at lines 248–268.
- Severity: **Low**

**`ParentPanelController.awakeFromNib()`** — `Panel/ParentPanelController.swift:103–146`
- 4-level nested conditionals checking slider visibility and preferences at lines 128–138.
- Severity: **Low**

---

### Magic Numbers and Strings

**`ParentPanelController`** — `Panel/ParentPanelController.swift`
- Line 233: `68.0` (row height threshold, used 3 times)
- Line 248: `90` (row height cap)
- Line 259: `8.0` (sunrise spacing)
- Lines 283, 295, 303, 307: `100.0`, `100`, `200`, `300` (scroll view margins) — no named constants
- Severity: **Medium**

**`AppearanceViewController`** — `Preferences/Appearance/AppearanceViewController.swift:38`
- Static array `[1, 2, 3, 4, 5, 6, 7, 14, 30, 90]` (relative date options) without named constant.
- Severity: **Low**

**`TimezoneCellView`** — `Panel/UI/TimezoneCellView.swift:147–148`
- `1` and `2` multipliers used directly in font size calculation without explanation.
- Severity: **Low**

---

### Primitive Obsession

**`TimezoneAdditionHandler` — dictionary construction** — `Preferences/General/TimezoneAdditionHandler.swift:102–109, 224–232, 329–337`
- The same 7-key `[String: Any]` dictionary (`latitude`, `longitude`, `timezoneID`, `timezoneName`, `placeIdentifier`, `nextUpdate`, `customLabel`) is constructed in three separate places. These fields constitute a complete model that should be a typed struct, not a repeated ad-hoc dictionary.
- Severity: **High**

**`PanelController.log()`** — `Panel/PanelController.swift:278–290`
- Retrieves 8 separate `NSNumber?` values from UserDefaults in a single guard, all belonging to the same display-preference concern. Should be a preference struct.
- Severity: **Medium**

---

## Logic Antipatterns

### Boolean Blindness

**NSNumber integer comparisons without semantic labels**

**`ParentPanelController`** — `Panel/ParentPanelController.swift:132–135`
- Compares `value.intValue` against literal `1`/`0` to show/hide the future slider container. The boolean intent (`displayFutureSlider`) is lost in the raw integer comparison.
- Severity: **High**

**`TimezoneDataOperations`** — `Panel/Data Layer/TimezoneDataOperations.swift:241, 255, 277, 282`
- Multiple comparisons against integers `0`, `1`, `2`, `3` for `relativeDayPreference.intValue`. These map to distinct display modes (Today/Yesterday/Tomorrow, day name, date format, hidden) but have no named enum or constant; the meaning requires cross-referencing `AppDefaults`.
- Severity: **High**

**`TimezoneDataSource`** — `Panel/UI/TimezoneDataSource.swift:102`
- `userFontSize == 4` is a magic comparison determining the default row height. `4` is the default font size constant but appears unrecognisable here without context.
- Severity: **Medium**

**`DataStore`** — `Overall App/DataStore.swift:127`
- Boolean logic encoded as `$0 != 1` on a retrieved `NSNumber` without semantic context.
- Severity: **Medium**

---

### Null Returns for Collections

**`DataStore.menubarTimezones()`** — `Overall App/DataStore.swift:71–74`
- Returns `[Data]?` even though the code comment states it always returns non-nil. Callers defensively append `?? []` throughout (e.g., `StatusItemHandler.swift:245, 317`). The return type should be `[Data]`.
- Severity: **Medium**

---

### Stringly Typed Code

**`TimezoneAdditionHandler` — inconsistent key constants** — `Preferences/General/TimezoneAdditionHandler.swift:228–230`
- Inside the 7-key dictionary, some keys use `UserDefaultKeys` constants while others use raw string literals: `"latitude"`, `"longitude"`, `"nextUpdate"` are bare strings with no corresponding constants.
- Severity: **High**

**`TimezoneData.init(with:)`** — `CoreModelKit/Sources/CoreModelKit/TimezoneData.swift:101–121`
- Initializer accepts `[String: Any]` with arbitrary string keys; callers must know the magic key names. `ModelConstants` defines some keys but not all, and the split responsibility creates mismatch risk.
- Severity: **High**

**`TimezoneAdditionHandler` — error classification by string** — `Preferences/General/TimezoneAdditionHandler.swift:134`
- Error handling compares `errorMessage == PreferencesConstants.offlineErrorMessage`, a string-equality check against a localised message. Fragile to wording changes.
- Severity: **Medium**

---

## Security Antipatterns

### SQL Injection

No findings. The app uses no CoreData, SQLite, or raw SQL.

---

### Hardcoded Credentials

No findings. No API keys, tokens, or passwords found in source.

---

### Unsafe Deserialization

**Drag-and-drop pasteboard deserialization** — `Preferences/General/PreferencesDataSource.swift:69`
- `NSKeyedUnarchiver.unarchivedObject(ofClass: NSIndexSet.self, from: data)` operates on data from the local pasteboard, which other apps running as the same user can write to. The class whitelist (`NSIndexSet`) limits exploitability, but the data origin is technically untrusted.
- Severity: **Low**

**Fixed-path temp file, no cleanup** — `Preferences/About/AboutView.swift:219`
- `FileManager.default.temporaryDirectory.appendingPathComponent("meridian-log.txt")` writes a predictable, fixed filename with no randomisation. The file persists indefinitely after export. Any other process running as the same user can read it.
- Severity: **Low**

---

### Missing Input Validation

**`search()` length check not enforced at call site** — `Preferences/General/TimezoneAdditionHandler.swift:65–87`
- `maxSearchLength = 50` is enforced only inside `filterArray()` (the debounced path). The `search()` method itself has no length check and is an `@objc` selector callable independently, allowing an arbitrarily long string to reach `CLGeocoder`.
- Severity: **Low**

**Timezone identifier not validated against known list** — `CoreModelKit/Sources/CoreModelKit/TimezoneData.swift:284`
- `isDaylightSavings()` calls `TimeZone(abbreviation: timezone())` where `timezone()` returns any string stored in `timezoneID`. An unexpected identifier silently falls back to the auto-updating timezone, producing incorrect time display with no user-visible error.
- Severity: **Low**

---

### macOS-Specific Concerns

**`com.apple.security.network.server` entitlement present unnecessarily** — `App/Meridian.entitlements:9–10`
- The app makes only outbound requests (CLGeocoder, Sparkle). No server-side socket code exists. This entitlement unnecessarily expands the sandbox attack surface.
- Severity: **Medium**

**All OSLog messages marked `%{public}`** — `CoreLoggerKit/Sources/CoreLoggerKit/Logger.swift:13, 19`
- Both `Logger.production` and `Logger.debug` emit all messages as public, meaning user-entered search strings and resolved place names are visible to any process with `OSLogStore` access (admin/diagnostic tools). No credentials are logged, but inferred user location is.
- Severity: **Low**

**Log export temp file never cleaned up** — `Preferences/About/AboutView.swift:219–222`
- After writing and revealing `meridian-log.txt`, no `defer` or follow-up deletion occurs. Each export overwrites the same path but a prior version persists on write failure. Up to 7 days of log entries (including place names) accumulate until the OS clears temp.
- Severity: **Low**

---

## Performance Antipatterns

### N+1 Deserialization in Hot Paths

**1-second timer tick deserializes every timezone on every tick** — `Panel/ParentPanelController.swift:449–457`
- `updateTime()` calls `TimezoneData.customObject(from:)` for every timezone every second. For N timezones this is N `NSKeyedUnarchiver` calls per second, indefinitely.
- Severity: **High**

**`MenubarTitleProvider.titleForMenubar()` deserializes every menubar timezone per tick** — `Preferences/Menu Bar/MenubarTitleProvider.swift:25–29`
- Called from the 1-second timer in standard text mode. Deserializes each menubar timezone, constructs a `TimezoneDataOperations` object, and calls `menuTitle()` — all allocating on the main thread every second.
- Severity: **High**

**Multiple UserDefaults reads inside timer tick** — `Panel/ParentPanelController.swift:435–436`
- `updateTime()` calls `dataStore.menubarTimezones()` → `dataStore.timezones()` → `UserDefaults` read, plus `updateMenubar()` triggering further preference reads, all synchronously on the main thread every second.
- Severity: **High**

**`setScrollViewConstraint()` deserializes all timezones during layout** — `Panel/ParentPanelController.swift:275–278`
- Loops through all timezone `Data` objects calling `TimezoneData.customObject(from:)` to calculate row heights on every constraint update.
- Severity: **Medium**

**`getAdjustedRowHeight()` reads UserDefaults per row in a loop** — `Panel/ParentPanelController.swift:228`
- Calls `dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference)` on each invocation; called for every row during layout, resulting in repeated synchronous UserDefaults reads in a loop.
- Severity: **Medium**

**`updateDefaultPreferences()` triggers multiple deserialize passes** — `Panel/ParentPanelController.swift:372`
- Deserializes all timezones via `compactMap`, then `updateDatasource()` at line 389 may trigger further deserialization for height recalculation.
- Severity: **Medium**

---

### Synchronous I/O / Expensive Allocations in Render Path

**`StatusItemView` attributes dictionary rebuilt on every update** — `Preferences/Menu Bar/StatusItemView.swift:56–78`
- `timeAttributes` and `textFontAttributes` computed properties rebuild the attributes dictionary on every access during menubar refresh. These should be stored constants.
- Severity: **Medium**

**`TimezoneCellView.setupTextSize()` reads DataStore.shared() per cell layout** — `Panel/UI/TimezoneCellView.swift:135`
- Reads `UserDefaults` via `DataStore.shared().retrieve()` on every cell layout update, called multiple times per render cycle.
- Severity: **Medium**

**`StatusContainerView.containerWidth()` runs full deserialization + text measurement on init** — `Preferences/Menu Bar/StatusContainerView.swift:94–116`
- Deserializes all timezones, constructs `TimezoneDataOperations` objects, calls `compactMenuTitle()`/`compactMenuSubtitle()` (date calculations), and measures text sizes at initialisation time.
- Severity: **Medium**

---

### Unbounded Collections

No findings. Collections are bounded by the user's timezone list (persisted in UserDefaults).

---

## Testing Antipatterns

### Test Code Duplication

**Computed fixture properties regenerate on every access** — `MeridianUnitTests/MeridianUnitTests.swift:20–45`
- Timezone fixture data and `TimezoneDataOperations` objects are defined as computed properties, recreating on every test access instead of using `setUp`.
- Severity: **Medium**

**Duplicated `tearDown` filter logic across test classes** — `MeridianUnitTests/MeridianUnitTests.swift:9–18`, `MeridianUnitTests/AppDelegateTests.swift:18–27`
- Identical DataStore cleanup code (filter by `formattedAddress` or `placeID`, reset timezones) duplicated rather than extracted to a shared helper.
- Severity: **Low**

---

### Testing Implementation Instead of Behavior

**Test manipulates `NSKeyedArchiver` internal `$objects` array** — `MeridianUnitTests/MeridianUnitTests.swift:423–467`
- `testDeserializationWithInvalidSelectionType` directly walks the private archive plist structure to inject an invalid `selectionType` value of `999`. Tests the internal NSCoding encoding format, not the public deserialization contract.
- Severity: **High**

**Test asserts on internal subview count and animation keys** — `MeridianUnitTests/MeridianUnitTests.swift:404–411`
- `testNoTimezoneView` asserts on exact subview count (`2`), specific layer animation key (`"notimezone.emoji"`), and internal view hierarchy. These are internal implementation details, not observable behavior.
- Severity: **Medium**

**Test asserts on internal button state** — `MeridianUnitTests/AppDelegateTests.swift:76–93`
- `testMenubarInvalidationToIcon` asserts on `toolTip`, `imagePosition`, and `subviews` array of the status item button — implementation details of the state machine, not the observable outcome.
- Severity: **Medium**

**Test asserts on call sequence and intermediate state** — `MeridianUnitTests/AppDelegateTests.swift:120–151`
- `testStandardModeMenubarSetup` calls `setupMenubarTimer()` twice and asserts different internal states between calls; depends on prior test state via `olderTimezones.isEmpty`.
- Severity: **Medium**

---

### Dependencies on Real Singletons

**`GlobalShortcutMonitor.shared` used directly** — `MeridianUnitTests/GlobalShortcutMonitorTests.swift:139, 160, 175`
- Tests use the real singleton and mutate `UserDefaults.standard` directly (lines 12, 17, 142, 158, 178, 183). State leaks between tests if run in sequence.
- Severity: **High**

**`DataStore.shared()` used in core format tests** — `MeridianUnitTests/MeridianUnitTests.swift:12, 28, 32, 36, 40, 44, 170, 181, 190, 200–227`
- `testTimezoneFormat`, `testTimezoneFormatWithDefaultSetAs24HourFormat`, `testSecondsDisplayForOverridenTimezone` all call `DataStore.shared().timezoneFormat()` and modify `UserDefaults.standard` directly, coupling tests to global app state.
- Severity: **High**

**`NSApplication.shared` used in AppDelegate tests** — `MeridianUnitTests/AppDelegateTests.swift:14, 30, 36, 57, 64`
- Tests access the real `NSApplication.shared` and call `continueUsually()` in `setUp` to initialise global app state. Tests depend on the app delegate's full initialisation.
- Severity: **High**

---

### Weak Assertion Patterns and Smoke Tests

**`testWithAllLocales` only asserts not-nil** — `MeridianUnitTests/MeridianUnitTests.swift:351–360`
- Iterates all available locales and only asserts `XCTAssertNotNil(localizedDate)`. No assertion on format correctness or locale-specific behavior — just verifies no crash.
- Severity: **Medium**

**`isEmpty == false` pattern instead of `XCTAssertFalse(isEmpty)`** — `MeridianUnitTests/MeridianUnitTests.swift:82`, `MeridianUnitTests/SearchDataSourceTests.swift:39, 43, 47`
- Weaker assertion pattern reduces readability and degrades failure messages.
- Severity: **Low**

---

### Missing Coverage for Key Behaviors

**DST transition test only validates string format, not accuracy** — `MeridianUnitTests/TimezoneDataOperationsTests.swift:250–261`
- `testNextDaylightSavingsTransitionFormat` only checks that the string starts with `"Heads up:"` and contains `"DST transition"`. The transition date and calculation accuracy are never validated.
- Severity: **Medium**

**Sunrise/sunset test does not validate calculated values** — `MeridianUnitTests/TimezoneDataOperationsTests.swift:206–227`
- Tests only verify `formattedSunriseTime` is not empty. No assertion against known sunrise/sunset times for specific dates and coordinates.
- Severity: **Medium**

---

## Async Antipatterns

### Floating Tasks

**`Task.detached` at launch not stored or cancellable** — `AppDelegate.swift:19–22`
- `Task.detached(priority: .utility)` runs `checkForPreviousUncleanExit()` and `writeSentinelFile()` at launch with no stored reference. No cancellation is possible if the app terminates quickly; errors are silently lost.
- Severity: **Medium**

---

### Callback Hell

No findings. The codebase has fully migrated to async/await. No callback nesting beyond 1 level exists.

---

### Async in Constructor

No findings.

---

### Missing `@MainActor` on UI Update in Async Callback

**`LocationController` — CLGeocoder callback updates DataStore from unspecified thread** — `App/LocationController.swift:76–80`
- The `reverseGeocodeLocation()` completion handler calls `self.updateHomeObject(with:coordinates:)` without dispatching to the main actor. The enclosing method has no `@MainActor` annotation, so the DataStore write may occur on a background thread, creating a potential race condition.
- Severity: **High**

---

### Legacy Completion Handler Instead of async/await

**`LocationController.reverseGeocodeLocation` uses callback-based API** — `App/LocationController.swift:76–80`
- Uses the legacy closure-based `CLGeocoder.reverseGeocodeLocation(_:completionHandler:)` instead of the async/await overload available since iOS 15 / macOS 12. Mixes async patterns unnecessarily.
- Severity: **Low**

---

## Summary

| Section | High | Medium | Low | Total |
|---------|------|--------|-----|-------|
| Structural | 4 | 9 | 4 | 17 |
| Logic | 2 | 3 | 2 | 7 |
| Security | 0 | 1 | 6 | 7 |
| Performance | 3 | 6 | 0 | 9 |
| Testing | 3 | 6 | 2 | 11 |
| Async | 1 | 1 | 1 | 3 |
| **Total** | **13** | **26** | **15** | **54** |

### Top priorities

1. **God Classes** (Structural) — `ParentPanelController`, `TimezoneAdditionHandler`, `PreferencesViewController` remain the largest structural debt. Breaking these up would improve testability across multiple categories simultaneously.
2. **Per-tick allocations** (Performance) — N+1 deserialization and UserDefaults reads in the 1-second timer are the highest-impact runtime issues. Caching deserialized models between ticks would eliminate this.
3. **Real singletons in tests** (Testing) — Three test classes depend on `DataStore.shared()`, `GlobalShortcutMonitor.shared`, and `NSApplication.shared`. Injecting test doubles here would unblock reliable parallel test runs and remove DST / time-of-day fragility.
4. **Missing `@MainActor`** (Async) — `LocationController`'s geocoder callback updates shared state off the main thread, a real concurrency hazard.
5. **Unnecessary `network.server` entitlement** (Security) — Safe to remove; no inbound socket usage exists.
