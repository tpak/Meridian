# Tech Debt to Remediate

Generated 2026-04-30 via four-agent parallel code review (security, dead code, resilience, maintainability).

**Status as of 2026-05-01**: 12 items shipped in v2.21.1 (PRs #108, #109) and #110 (R9). 2 items skipped as not-urgent for this use case. 1 item retired as already-done. **8 items remain**, all in the "needs design judgment" bucket.

---

## Status Summary

| Item | Status | Where |
|------|--------|-------|
| S1 | ✅ Done | PR #108 (v2.21.1) |
| S2 | ✅ Done | PR #109 (v2.21.1) |
| S3 | ⏭️ Skipped | Not urgent for current use case |
| S4 | ⏭️ Skipped | Already mitigated by `Logger.debug` wrapping; per-component os.Logger refactor not urgent |
| R1, R2, R3, R4 | ✅ Done | PR #109 (v2.21.1) |
| R5 | ✅ Done | PR #109 (v2.21.1) |
| R6 | ✅ Done | PR #109 (v2.21.1) |
| R7 | ✅ Already done | `@available(*, unavailable)` already present in code |
| R8 | ✅ Done | PR #109 (v2.21.1) |
| R9 | ✅ Done | PR #110 |
| M2, M3, M4 | ✅ Done | PR #109 (v2.21.1) |
| M10 | ✅ Done | PR #108 (v2.21.1) |
| Dead Code | ✅ Done | PR #109 (v2.21.1) |
| M1, M5, M6, M7, M8, M9, M11, M12 | ⏳ Pending | Need design judgment — see below |

---

## Remaining Items (8)

### M1 — Implicitly unwrapped optional `statusBarHandler`
- **File:** `Meridian/AppDelegate.swift:11`
- **Issue:** `private var statusBarHandler: StatusItemHandler!` is an IUO initialized in `continueUsually()` called from `applicationDidFinishLaunching`. Any access before initialization crashes.
- **Fix:** Convert to `lazy var statusBarHandler: StatusItemHandler = StatusItemHandler()` with the initializer inline, eliminating the IUO entirely.

### M5 — Swizzle machinery inside DataStore
- **File:** `Meridian/Overall App/DataStore.swift:295–342`
- **Issue:** `method_exchangeImplementations` and `NSDynamicSystemColor` cache invalidation live inside a class whose job is preference storage. These are unrelated concerns that make DataStore hard to test in isolation.
- **Fix:** Extract to an `AccentColorSwizzler` type with a single `install()` call from AppDelegate.

### M6 — Magic numbers: delay literals and layout offsets
- **Files:** `Meridian/AppDelegate.swift:47` (`0.3`), `Meridian/Preferences/Appearance/AppearanceViewController.swift:308` (`0.2`), `Meridian/Panel/PanelController.swift:268` (`100`), `Meridian/Preferences/Menu Bar/StatusItemView.swift` (`0.92`)
- **Issue:** Hardcoded timing and layout values scattered across files — brittle and unexplained.
- **Fix:** Create a `TimingConstants` enum (`pauseBeforeRelaunch`, `panelRepositionDelay`) and a `LayoutConstants` enum. Add a one-line comment on any value that isn't self-evident.

### M7 — Duplicated `init?(jsonName:)` across 5 enums
- **File:** `Meridian/Overall App/DataStore.swift` (5 enum extensions)
- **Issue:** The 6-line pattern is copy-pasted verbatim into `MenubarMode`, `Theme`, `RelativeDateDisplay`, `AppPresentation`, and `TimeFormat`.
- **Fix:** Define a `JSONNameDecodable` protocol with a default implementation; each enum's conformance is a single line.

### M8 — Mixed async dispatch styles
- **Files:** `Meridian/Preferences/General/PreferencesViewController.swift:124–132`, `Meridian/Preferences/Appearance/AppearanceViewController.swift:402–413`, `Meridian/Panel/PanelController.swift:371–375`
- **Issue:** `OperationQueue.main.addOperation { }` used alongside `Task { @MainActor in }` and `DispatchQueue.main.async { }` — three different patterns for the same thing.
- **Fix:** Standardize on `Task { @MainActor in }` in async contexts and `DispatchQueue.main.async` in sync contexts. Retire all `OperationQueue.main` usage.

### M9 — Mixed notification subscription styles
- **Files:** `Meridian/Panel/PanelController.swift:57–64`, `Meridian/Panel/ParentPanelController+ModernSlider.swift:61–64`
- **Issue:** `NSNotificationCenter.addObserver(selector:)` mixed with Combine `.publisher()` sinks — two different unsubscription lifecycles to reason about.
- **Fix:** Migrate the remaining `addObserver` calls to Combine `.publisher()` sinks stored in `cancellables`. The Combine pattern already dominates the file.

### M11 — Over-exposed properties in ParentPanelController
- **File:** `Meridian/Panel/ParentPanelController.swift:14–54`
- **Issue:** `cancellables`, `futureSliderValue`, `parentTimer`, `datasource`, `currentCenterSliderItemIndex` are all `var` or `public var` — most have no callers outside the class.
- **Fix:** Default all to `private`; promote only the handful genuinely needed by the subclass or tests.

### M12 — `search()` method is 61 lines with multiple responsibilities
- **File:** `Meridian/Preferences/General/TimezoneAdditionHandler.swift:63–123`
- **Issue:** One method handles input validation, UI feedback, network call, and error handling sequentially.
- **Fix:** Extract `validateSearchInput() -> Bool`, `showSearchInProgress()`, and `presentNetworkError(_:)` sub-methods. The main `search()` becomes an orchestrator.

---

## Skipped — Not Urgent for Current Use Case

### S3 — Settings import applies unvalidated JSON values
- **File:** `Meridian/Overall App/SettingsManager.swift:176–315`
- **Issue:** `applySettings(from:)` deserializes via broad `as? [String: Any]` casts and copies values into UserDefaults with minimal type or range checking. A crafted file could inject unexpected types or out-of-range values.
- **Original fix:** Add a validation pass before `applySettings(from:)` — check value types, enforce valid ranges, verify timezone identifiers are in `TimeZone.knownTimeZoneIdentifiers`, and reject unknown keys.
- **Why skipped:** Settings import is an explicit user action with a file the user themselves chose. No remote-injection vector. Can revisit if Meridian ever auto-imports settings from a URL or pasteboard.

### S4 — PII logged without privacy annotation
- **Files:** `Meridian/Preferences/General/TimezoneAdditionHandler.swift:242,344,399`, `Meridian/AppDelegate.swift:135`
- **Original fix:** Apply `\(value, privacy: .private)` annotations using `os.Logger`.
- **Why skipped:** Already mitigated. `CoreLoggerKit.Logger.debug` always wraps the entire interpolated message via `os_log "%{private}@"`, so city names and timezone identifiers are already redacted in `log stream` output for non-privileged readers. Per-component `os.Logger` annotations would require restructuring the Logger API for marginal benefit.

---

## Completed Reference (for grep)

The following items shipped in v2.21.1 (PRs #108, #109) and #110:
- **S1, S2** — URL encoding hardened, exported debug log file restricted to user-only permissions.
- **R1, R2, R3, R4** — 14 force-unwraps replaced with safe guards in `Date+TimeAgo.swift` and `SearchDataSource.swift`.
- **R5, R6, R8** — Observer cleanup in `PanelController` deinit, timer invalidation in `StatusItemHandler.updateMenubar`, bounds-check on `TimezoneDataSource` row subscript.
- **R9** — Timeout race added to `CLGeocoder` reverse and forward geocode calls; silent `try?` replaced with logged errors.
- **M2, M3, M4** — `notimezoneView`→`noTimezoneView`, `currentCenterIndexPath`→`currentCenterSliderItemIndex`, `setFrameTheNewWay()`→`positionPanelRelativeToStatusItem()`.
- **M10** — Three slider tooltip strings localized via `Localizable.xcstrings`.
- **Dead Code** — Removed `installHomeIndicatorObject`, `defaultMenubarMode`, `switchToCompactModeAlert`, `OriginalProjectURL`, `CrowdInLocalizationLink`.

R7 (`@available(*, unavailable)` on `required init?(coder:)`) was already present in `Toasty`, `StatusItemView`, and `StatusContainerView` — the audit was based on a stale snapshot.
