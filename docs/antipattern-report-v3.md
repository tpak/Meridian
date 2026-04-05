# Meridian Codebase Antipattern Report — v3

**Date:** 2026-04-05
**Codebase version:** v2.17.1
**Analysis basis:** [common_antipatterns.md](https://github.com/alirezarezvani/claude-skills/blob/main/engineering-team/code-reviewer/references/common_antipatterns.md)

> v3 reflects the state of the codebase after all three rounds of fixes (PR #71, PR #72). This is a full re-scan.

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

The three god classes identified in v2 remain structurally large. `ParentPanelController` was split into extension files but the combined surface is still wide. These are acknowledged trade-offs — further decomposition would require extracting into separate types with delegate protocols, which carries regression risk disproportionate to the benefit for a ~11K-line codebase.

| Severity | File | Lines | Notes |
|----------|------|-------|-------|
| Medium | `Panel/ParentPanelController.swift` + extensions | 786 combined | Split across 4 files (+Layout, +Actions, +ModernSlider). Concerns are separated by file but the class remains a single type. |
| Medium | `Panel/PanelController.swift` | 529 | Subclasses ParentPanelController. Combined with parent exceeds 1300 lines. |
| Medium | `Preferences/General/PreferencesViewController.swift` | 454 | 6 extensions with MARK separation. Within SwiftLint threshold. |
| Low | `Preferences/General/TimezoneAdditionHandler.swift` | 476 | Already extracted from PreferencesViewController. Search + install concerns overlap. |
| Low | `Preferences/Appearance/AppearanceViewController.swift` | 406 | Preview table in its own extension. Within SwiftLint threshold. |

---

### Long Method

| Severity | File | Line(s) | Method | Lines |
|----------|------|---------|--------|-------|
| Medium | `Panel/PanelController.swift` | 167-228 | `open()` | 62 — resets animations, syncs state, configures slider, sets frame, starts timer, logs |
| Low | `Panel/PanelController.swift` | 260-330 | `LogDisplayPreferences.init` + `log()` | 70 combined with the struct extraction |
| Low | `Dependencies/Solar.swift` | 67-161 | `calculate()` | 95 — vendored dependency, not project code |

---

### Deep Nesting

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `Panel/PanelController.swift` | 189-197 | `open()`: 4 levels for slider visibility logic |
| Low | `Panel/ParentPanelController.swift` | 339-357 | `updateTime()`: `forEach` closure adds nesting layer vs a `for` loop |
| Low | `Overall App/GlobalShortcutMonitor.swift` | 70-94 | `currentShortcut` getter: 5 logical levels for legacy migration path |

---

### Magic Numbers and Strings

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `Panel/UI/TimezoneDataSource.swift` | 93-122 | Row height uses bare `100`, `60`, `65`, `5`, `8`, `15`, `2` — same role as `PanelLayoutConstants` in +Layout.swift but not unified |
| Medium | `Preferences/Menu Bar/StatusContainerView.swift` | 8-38 | `compactWidth()` uses bare `55`, `12`, `20`, `15`, `30` — duplicates `BufferWidthConstants` in StatusItemHandler |
| Medium | `Panel/UI/TimezoneCellView.swift` | 88-115 | Constraint adjustments use `12`, `15`, `-5.0`, `-10.0`, `-15.0`, `-3.0` with no named constants |
| Low | `Panel/ParentPanelController.swift` | 154 | `cornerRadius = 12.0` — bare literal |
| Low | `Preferences/About/AboutView.swift` | 17 | `[86400, 604800, 2592000]` — update interval seconds without readable computation |
| Low | `Panel/ParentPanelController+Layout.swift` | 47, 51 | `60.0` and `fontSize == 4` not using existing `PanelLayoutConstants` |
| Low | `Overall App/DataStore.swift` | 42-46 | `timeFormatsWithSuffix` uses NSNumber index literals with no explanatory constants |
| Low | `CoreModelKit/.../TimezoneData.swift` | 65-81 | `values` dictionary uses NSNumber(0)..NSNumber(11) keys without named constants |

---

### Primitive Obsession

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `CoreModelKit/.../TimezoneData.swift` | 228-252 | `setShouldOverrideGlobalTimeFormat(_ shouldOverride: Int)` — 11-branch if-else chain mapping raw Int to `TimezoneOverride` enum. Parameter should be the enum directly. |
| Low | `CoreModelKit/.../TimezoneData.swift` | 149-165 | `TimezoneData.make()` takes 7 parameters (4 String, 2 Double, 1 String). Represents a structured location concept. |
| Low | `Panel/Data Layer/TimezoneDataOperations.swift` | 332-333 | `formatOffset()` takes 5 parameters (3 String, 2 NSDate) — related formatting context. |

---

## Logic Antipatterns

### Boolean Blindness

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| High | `Panel/ParentPanelController+ModernSlider.swift` | 73, 84 | `animateButton(_ hidden: Bool)` and `showAccessoryButtonsIfNeccesary(_ hide: Bool)` — unlabeled `_` parameters called with bare `true`/`false`. `show...(_ hide:)` has inverted semantics. |
| Medium | `AppDelegate.swift` | 227 | `invalidateMenubarTimer(_ showIcon: Bool)` — `_` parameter label means callers read `invalidateMenubarTimer(false)` with no indication of meaning. |

---

### Null Returns for Collections

No findings. All collection-returning functions return non-optional types.

---

### Stringly Typed Code

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| High | `CoreModelKit/.../TimezoneData.swift` | 108 | `init(with dictionary: [String: Any])` still exists. Used by `TimezoneSearchService.swift:45-52`. Typo in any key silently produces `"Error"` fallback string. |
| Medium | `Panel/Data Layer/TimezoneDataOperations.swift` | 337-338 | `preferredLanguageCode != "en"` / `== "de"` — raw string comparisons for locale branching |
| Medium | `Panel/PanelController.swift` | 306-324 | `log()` builds a `[String: Any]` analytics dictionary with string values like `"Default"`/`"Black"` derived from integer comparisons, instead of using existing enums |
| Medium | `CoreModelKit/.../TimezoneData.swift` | 110, 121-122 | `"Error"` sentinel string as default when dictionary parsing fails — can silently propagate through UI |

---

## Security Antipatterns

### SQL Injection
No findings.

### Hardcoded Credentials
No findings.

### Unsafe Deserialization
No findings. All `NSKeyedUnarchiver` usage requires secure coding with class whitelists.

### Missing Input Validation
No findings. Search input is length-checked at both call sites; coordinates are range-clamped; custom labels are truncated.

### macOS-Specific Concerns

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Low | `Preferences/About/AboutView.swift` | 40-50 | Locale region identifier logged via `Logger.debug` — minor PII (two-letter country code). Debug logger uses `%{private}@` so redacted in Console.app, but "Export Log" may include unredacted messages. |

Sandbox entitlements are minimal and correct. No unnecessary entitlements. No credentials in logs. TLS used everywhere. No sensitive data in UserDefaults.

---

## Performance Antipatterns

### N+1 / Per-Tick Allocations

The major N+1 deserialization issue (NSKeyedUnarchiver per cell per tick) was fixed in v2.17.1 with `timezoneObjects()` caching. Remaining findings are about lightweight object allocations, not I/O.

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `Preferences/Menu Bar/StatusItemView.swift` | 42-44 | `operationsObject` is a computed property creating new `TimezoneDataOperations` on every access. Accessed 4 times per update per menubar timezone. |
| Medium | `Preferences/Menu Bar/StatusContainerView.swift` | 159 | `setNeedsDisplay(_:)` clears `cachedBestWidth` entirely, defeating the cache on every display cycle. `adjustWidthIfNeccessary()` then recomputes per subview every tick. |
| Low | `Panel/ParentPanelController.swift` | 365 | `updateCell()` creates new `TimezoneDataOperations` per visible cell per tick. Object is lightweight but triggers multiple `store.shouldDisplay()` → UserDefaults reads. |
| Low | `Preferences/Menu Bar/MenubarTitleProvider.swift` | 23 | New `TimezoneDataOperations` per menubar timezone per tick. Same lightweight allocation pattern. |
| Low | `Panel/ParentPanelController.swift` | 376-378 | `NSImage(systemSymbolName:)` called per cell per tick for sunrise/sunset icons. Likely cached by AppKit internally. |

### Unbounded Collections

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Low | `Panel/Data Layer/TimezoneDataOperations.swift` | 21-22 | `sunriseCache` and `dstCache` static dictionaries grow unbounded (keyed by timezone+date). Negligible in practice for a few timezones over months. |

### Synchronous I/O in Hot Paths

No findings. DataStore uses cached arrays. UserDefaults reads go through the in-process plist cache.

---

## Testing Antipatterns

### Test Code Duplication

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `MeridianUnitTests/PreferencesStoryboardTests.swift` | 11-91 | Every test method (10/10) repeats the same 3-line storyboard instantiation. No `setUp()` method exists. |
| Low | `MeridianUnitTests/MenubarTitleProviderTests.swift` | 37-125 | Six tests repeat the `TimezoneData(with:)` + `isFavourite = 1` + `addTimezone()` pattern. |

### Testing Implementation Instead of Behavior

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Low | `MeridianUnitTests/AppDelegateTests.swift` | 93-94 | Asserts on `subviews == []` and `toolTip == "Meridian"`. Acknowledged as implementation detail in comments. |

### Dependencies on Real Singletons

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `MeridianUnitTests/AppDelegateTests.swift` | 100-150 | `DataStore.shared()` + `UserDefaults.standard` in test methods. Documented as integration tests. |
| Medium | `MeridianUnitTests/AppDelegateTests.swift` | 18-134 | `NSApplication.shared.delegate` as test subject. Cannot be isolated by design. |
| Low | `MeridianUnitTests/GlobalShortcutMonitorTests.swift` | 143-178 | `GlobalShortcutMonitor.shared` + `UserDefaults.standard`. Documented trade-off (Carbon event tap singleton). |

### Tests Without Assertions

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Low | `MeridianUnitTests/LocationControllerTests.swift` | 38-46, 135-139 | Three methods (`testSetDelegate`, `testDetermineAndRequestLocation...`, `testDidFailWithError`) have no assertions — smoke tests only. |
| Medium | `MeridianUnitTests/NetworkManagerAsyncTests.swift` | 186-211 | Two tests hit `httpbin.org` (external URL). On network failure they silently pass with zero assertions. Non-deterministic. |

### Weak Assertion Patterns

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| High | `MeridianUnitTests/MeridianUnitTests.swift` | 141-340 | 29 instances of `XCTAssertTrue(a == b)` remain where `XCTAssertEqual(a, b)` should be used. Concentrated in `testTimezoneFormat`, `testTimezoneFormatWith24Hour`, and `testFormattedLabel`. |
| Low | `MeridianUnitTests/StandardMenubarHandlerTests.swift` | 55 | `XCTAssertTrue(menubarString.count == 0)` instead of `XCTAssertEqual` |
| Low | `MeridianUnitTests/SearchDataSourceTests.swift` | 110 | Bare `XCTAssert(possibleOutcomes.contains(...))` |

---

## Async Antipatterns

### Floating Tasks

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Medium | `App/LocationController.swift` | 74 | `Task { @MainActor }` created in `didUpdateLocations` without being stored. Cannot be cancelled if the controller is deallocated during geocoding. |

### Callback Hell
No findings.

### Async in Constructor
No findings.

### Unnecessary Task.detached

| Severity | File | Line(s) | Description |
|----------|------|---------|-------------|
| Low | `AppDelegate.swift` | 20 | `Task.detached(priority: .utility)` for sync file I/O. Regular `Task {}` would suffice since AppDelegate is not `@MainActor`. Task is properly stored and cancelled. |

### Missing @MainActor
No findings. All Task blocks touching UI use `@MainActor`.

---

## Summary

| Section | High | Medium | Low | Total |
|---------|------|--------|-----|-------|
| Structural | 0 | 9 | 12 | 21 |
| Logic | 1 | 3 | 0 | 4 |
| Security | 0 | 0 | 1 | 1 |
| Performance | 0 | 2 | 4 | 6 |
| Testing | 1 | 4 | 6 | 11 |
| Async | 0 | 1 | 1 | 2 |
| **Total** | **2** | **19** | **24** | **45** |

### v2 → v3 comparison

| | v2 | v3 | Change |
|---|---|---|---|
| High | 13 | 2 | **-85%** |
| Medium | 26 | 19 | -27% |
| Low | 15 | 24 | +60% (deeper scanning surfaced more low-severity items) |
| Total | 54 | 45 | -17% |

### Remaining High-severity findings (2)

1. **Boolean Blindness** — `animateButton(_ hidden:)` / `showAccessoryButtonsIfNeccesary(_ hide:)` — inverted/unlabeled boolean params in ModernSlider
2. **Weak assertions** — 29 instances of `XCTAssertTrue(a == b)` remain in `MeridianUnitTests.swift`

### What was resolved since v2

- All N+1 deserialization (NSKeyedUnarchiver per tick) — **resolved** via `timezoneObjects()` cache
- All singleton test dependencies in `MeridianUnitTests` — **resolved** via MockDataStore migration
- `network.server` entitlement — **removed**
- Missing `@MainActor` on LocationController geocode — **resolved** via Task { @MainActor }
- `menubarTimezones()` optional return — **resolved** to non-optional
- `TimezoneData.make()` factory — **added**, replacing 3 dictionary sites
- `RelativeDayDisplay` / `FutureSliderDisplayState` enums — **added**, replacing raw int comparisons
- `isDaylightSavings()` bug (abbreviation vs identifier) — **fixed**
- `Logger.debug` privacy — **changed** to `%{private}@`
- Deep nesting in awakeFromNib, updateTimeTopSpace, setPanelFrame — **flattened**
- ParentPanelController split into +Layout.swift and +Actions.swift — **done**
- `LogDisplayPreferences` struct extraction — **done**
- Error classification by string → NSError code check — **done**
- Temp file UUID filename — **done**
- Sentinel task stored and cancellable — **done**
