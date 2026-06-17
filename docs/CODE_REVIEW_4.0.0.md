# Meridian 4.0.0 — Code Review (Dead Code, Security & Technical Debt)

> **Status:** Review only. **No source code was changed.** Every item below is a *proposal*.
> **Reviewed build:** `4.0.0-beta30` (branch `main` @ pre-GA) · **Date:** 2026-06-17
> **Tracking:** Each confirmed finding has a GitHub issue (label `code-review-4.0.0`). This document is the index.

## How this review was done

A multi-agent pass fanned out three independent finders (dead-code, security, technical-debt) plus a SwiftLint/clang-analyzer tooling run, then put **every** candidate through an *adversarial verifier* whose job was to **refute** it — grepping Swift call sites, `.storyboard`/`.xib` files, `#selector`/`NSSelectorFromString` usage, KVO/UserDefaults key strings, protocol conformances (`NSSecureCoding`, Sparkle delegate, table-view data sources), `@objc` exposure, and the test targets — before anything was confirmed. This is why, e.g., the v4 feature-flag scaffolding is **not** reported as dead code (it's referenced by tests and storyboards and is an intentional rollback lever — see *Considered & dismissed*).

| | Candidates | **Confirmed** | Refuted (false positive / intentional) |
|---|---:|---:|---:|
| Dead code | 17 | **15** | 2 |
| Security | 4 | **1** | 3 |
| Technical debt | 8 | **6** | 2 |
| **Total** | **29** | **22** | **7** |

**Severity of confirmed findings:** 0 critical · 0 high · **1 medium** · **21 low**.
**SwiftLint:** 79 warnings, **0 errors** (no `force_cast`/`force_try`). **clang static analyzer:** `ANALYZE SUCCEEDED`, **0 source warnings**.

This is a healthy codebase. There is **no urgent or shipping-blocking issue** here — the security finding is a low-sensitivity privacy nicety, and the rest is cleanup/consistency debt that can be paid down opportunistically. The single largest debt-reduction opportunity (retiring the v4 rollback scaffolding) is **deliberately deferred until after GA** — see the last section.

---

## Security (1)

### F18 — User-chosen city label / address written to the always-on public log · `low`
**`Meridian/Panel/Data Layer/TimezoneDataOperations.swift:353`** (logging primitive: `Meridian/CoreLoggerKit/Sources/CoreLoggerKit/Logger.swift:12-14`; secondary: `App/LocationController.swift:92,107`)

`Logger.production(_:)` formats with `os_log("%{public}@", …)`, so anything interpolated lands in the unified system log **unredacted** and is captured into the user-shareable **Export Log** bundle. Line 353 logs `dataObject.formattedTimezoneLabel()` — which returns the user's *custom label* (e.g. "Mom's house") or a geocoded *address/city*. The codebase already routes genuinely-sensitive label logging through the private/opt-in `Logger.debug` channel (`%{private}@`); line 353 is the lone deviation. Fires only when Solar returns nil sunrise/sunset (e.g. polar latitudes) — rare but real. Leaked data is low-sensitivity (a self-chosen label or city-level address, not credentials/GPS), hence **low**.

**Proposed fix** — log the non-identifying timezone identifier instead:
```swift
// TimezoneDataOperations.swift:353
Logger.production("Sunrise/Sunset Error: Unable to fetch sunrise/sunset for timezone \(dataObject.timezoneID ?? "unknown")")
```
For `LocationController.swift:92,107`, drop `error.localizedDescription` in favor of `(error as NSError).domain`/`.code`, or route through `Logger.debug`. Optional hardening: add a `Logger.private(_:)` convenience (always-on but `%{private}@`) and reserve `Logger.production` for non-PII text.

---

## Technical debt (6)

### F23 — v4 `com.tpak.meridian.v4.*` UserDefaults keys duplicated as raw literals, no single source of truth · **`medium`**
**`Meridian/Preferences/Menu Bar/StatusItemView.swift:39,44`** + 8 files

v4 preferences bypass the typed `UserDefaultKeys`/`AppDefaults` convention CLAUDE.md mandates, and the **same raw key string is hardcoded independently in 2–3 places** (13 literal sites across 8 files). Examples: `…v4.menubarStacked` is read raw in `StatusItemView.swift:39` *and* written via `@AppStorage("…v4.menubarStacked")` in `MenuBarPane.swift:105`; `…v4.snapStep`/`travelPastDays` live in `DaybreakDefaults.Keys` *and* are re-hardcoded in `TimeTravelPane.swift:12-13`; `…v4.textScale` is a literal in both `AppearancePane.swift:18` and `DaybreakRootView.swift:24`. `DaybreakDefaults.swift` itself documents this as temporary ("will be folded into DataStore's typed accessors … when the Settings window is rebuilt in Phase 3") — but Phase 3 shipped without the consolidation. **Latent desync hazard:** `DaybreakDefaults.snapStep`'s setter validates writes to `[5,15,30,60]`, but `TimeTravelPane.swift:13` writes the same key raw with no validation — two write paths, one key, divergent invariants. A typo in any literal silently desyncs the Settings UI from the renderer with **no compiler error**.

**Proposed fix:** make `DaybreakDefaults.Keys` the single canonical home for every `…v4.*` string (add the missing ones: `textScale`, `menubarStacked`, `menubarColorDots`, `menubarPreset`, `cityColors`, `daybreakFloatingTopLeft`). Replace all `@AppStorage("…literal…")` and raw `UserDefaults.standard.object(forKey:)` sites with `@AppStorage(DaybreakDefaults.Keys.X)` / the typed accessors. Reconcile the unvalidated `snapStep` write path. Register defaults in `AppDefaults`. (`DaybreakEngineTests.swift:294` already uses `DaybreakDefaults.Keys.snapStep`, so the canonical constant is test-compatible.)

### F29 — One-shot migration flags stored under raw, untyped UserDefaults keys in AppDelegate · `low`
**`Meridian/AppDelegate.swift:243,258,280,283`**

`"HasSetAutoUpdateDefault"`, `"HasFixedAutoUpdateSync"`, `"HasSetStartAtLoginDefault"` are read/written as inline string literals rather than via `UserDefaultKeys` (the Tahoe-onboarding and reopen-appearance flags *do* use typed constants, showing the inconsistency). The fresh-install detection cleverly reuses the *absence* of `"HasSetAutoUpdateDefault"` as a "brand-new install" proxy (line 283) — an implicit, load-bearing coupling between two unrelated flags (the launch-ordering dependency is even documented in a comment).

**Proposed fix:** add the three constants to `UserDefaultKeys` **preserving the exact string values** (changing them would re-fire the one-shot migrations for existing users), then reference them in AppDelegate. Optionally introduce an explicit `hasCompletedFirstLaunch` flag so start-at-login detection no longer depends on the auto-update flag's side effect.

### F24 — Panel update `Repeater` captures `self` strongly (retain cycle) · `low`
**`Meridian/Panel/PanelController.swift:374-378`**

`parentTimer = Repeater(…) { _ in DispatchQueue.main.async { self.updateTime() } }` captures `self` with no capture list. `Repeater` stores the observer closure strongly, and `self` owns `parentTimer`, so `PanelController → parentTimer → observers → closure → PanelController` is a cycle. **Dormant, not an active leak:** `PanelController` is a single app-lifetime instance and the timer is `nil`'d on minimize/close. It's inconsistent with the rest of the codebase, which correctly uses `[weak self]` (`StatusItemHandler.swift:343`, `DaybreakViewModel.swift:111`).

**Proposed fix:**
```swift
parentTimer = Repeater(interval: .seconds(1), mode: .infinite) { [weak self] _ in
    DispatchQueue.main.async { self?.updateTime() }
}
```

### F27 — Per-access allocation of `TimezoneDataOperations` on the live menu-bar render path · `low`
**`Meridian/Preferences/Menu Bar/StatusItemView.swift:63-65`**

`operationsObject` is a *computed* property that allocates a new `TimezoneDataOperations` and re-resolves `DataStore.shared()` on **every** access — 1× per timezone per tick in single-line mode, 2× in stacked mode, on a cadence that can be per-second. The object is cheap, so the win is modest (one alloc + one singleton lookup per tick); this is cleanup, not a perf fix.

**Proposed fix:** store the object and rebuild it in the existing `dataObject didSet` hook instead of recomputing per access. (The `shouldDisplay()`/UserDefaults reads inside the `compactMenu*` methods must still run every render and are unaffected.)

### F28 — Duplicated menu-bar layout magic numbers · `low`
**`Meridian/Preferences/Menu Bar/StatusContainerView.swift:8-38,100,164`**

`StatusContainerView.compactWidth` uses bare literals `55/12/20/20` that duplicate the named `BufferWidthConstants` (`baseWidth/dayBuffer/twelveHourBuffer/dateBuffer`) in `StatusItemHandler.swift:13-18`; both feed parallel buffer-width math for the stacked layout. **Scope correction (from verification):** the dot-padding `14` is *not* duplicated across both files (it lives only in `StatusContainerView`), there is no shared `30` constant, and the divergence is confined to the opt-in **Stacked** preset (default off). Real but minor.

**Proposed fix:** lift the shared geometry into one `enum MenubarLayoutConstants` referenced by both call sites.

### F25 — Deprecated `UserDefaults.synchronize()` call · `low`
**`Meridian/Preferences/Appearance/AppearanceViewController.swift:314`**

The only `synchronize()` in the codebase, in the accent-color restart flow. Deprecated/discouraged by Apple since 10.12; UserDefaults persists automatically (backed by `cfprefsd`, visible cross-process), so it confers no correctness benefit even before spawning the fresh instance. Doubly inert since this legacy VC is behind the `useV4Settings` kill-switch.

**Proposed fix:** delete the line. If/when the accent-restart flow is migrated to v4 settings, do not carry it over.

---

## Dead code (15)

All 15 are confirmed unreferenced anywhere (Swift, IB, selectors, KVO, protocols, tests) and are safe to remove. All **`low`** — harmless cleanup with no behavioral/security/build impact (where a build-system step is needed, it's noted).

| ID | Location | What | Note |
|----|----------|------|------|
| F1 | `Meridian/Overall App/Strings.swift:28` | `UserDefaultKeys.appleInterfaceStyleKey` (`"AppleInterfaceStyle"`) | Theme is observed via the `.interfaceStyleDidChange` notification, a *different* string. Clocker-era orphan. |
| F2 | `Meridian/Overall App/Strings.swift:11` | `UserDefaultKeys.dragSessionKey` (`"public.text"`) | Drag-and-drop uses the separate typed `NSPasteboard.PasteboardType.dragSession`. Duplicate. |
| F3 | `Meridian/Overall App/Strings.swift:33` | `UserDefaultKeys.nextUpdate` | Model archiving uses the *literal* `"nextUpdate"` coder key, not this constant. |
| F4 | `Meridian/Preferences/General/TimezoneAdditionHandler.swift:272-278` | `private func showMessage()` | No call sites; offline-error UX handled inline elsewhere. |
| F5 | `Meridian/Preferences/About/PointingHandCursorButton.swift` | `class PointingHandCursorButton` | Orphaned by the SwiftUI About migration; only reference is a test that exists to exercise it. |
| F6 | `Meridian/CoreModelKit/Sources/CoreModelKit/SearchResults.swift` | `ResultStatus` / `SearchResult` / `Timezone` (whole file) | Google Geocoding/Timezone REST models; obsolete since the switch to `CLGeocoder`. |
| F7 | `Meridian/Preferences/General/SearchDataSource.swift:21` | `private var dataTask: URLSessionDataTask?` | Never assigned/read; leftover from the old Google URLSession flow. |
| F8 | `Meridian/Overall App/DateFormatterManager.swift:7,8,12` | `calendarDateFormatter`, `simpleFormatter`, `gregorianCalendar` | Three unused statics; the *used* `gregorianCalendar` lives in `TimezoneDataOperations`. |
| F9 | `Meridian/Overall App/SettingsManager.swift:68-74` | `static func copySettingsToClipboard()` | No UI wires it; v4 settings only call `exportSettings()`/`importSettings()`. |
| F10 | `Meridian/Preferences/Menu Bar/StatusItemHandler.swift:67,320-322` | `hasActiveIcon` + `@objc setHasActiveIcon(_:)` | Write-only property + setter with no callers/KVC consumers. |
| F11 | `Meridian/Panel/PanelController.swift:398-400` | `func hasActivePanelGetter()` | Redundant wrapper; `hasActivePanel` is accessed directly. |
| F12 | `Meridian/Preferences/General/PreferencesViewController.swift:348-350` | `@IBAction func sortOptions(_:)` | Not connected in `Preferences.storyboard`; `additionalSortOptions` visibility is set directly. |
| F13 | `Meridian/Preferences/General/PreferencesViewController.swift:18` | `PreferencesConstants.hotKeyPathIdentifier` | Stale Cocoa-bindings KVC keypath; `GlobalShortcutMonitor` owns the real keys. |
| F14 | `Meridian/Preferences/General/PreferencesViewController.swift:17` | `PreferencesConstants.offlineErrorMessage` | Production-unused; kept alive only by a tautological localization test. |
| F15 | `Meridian/Panel/UI/Toasty.swift:97-99` | `enum ToastKeys { ActiveToast }` | Vestige of the upstream Toast-Swift associated-object key; never used. |

**Two dead-code items need a build-system step (not just a line delete):**
- **F5** — `PointingHandCursorButton.swift` is in the `.pbxproj` Sources phase and has a unit test (`MeridianUnitTests.swift` `testPointingHandButton`). Delete the file *from within Xcode* (prunes the 4 pbxproj refs) **and** remove the test, or the build/test breaks.
- **F14** — removal must touch **three** spots or `testAllActiveKeysResolveToNonEmptyStrings` fails: the constant (`PreferencesViewController.swift:17`), the assertion (`LocalizationTests.swift:74`), the `activeKeys` entry (`LocalizationTests.swift:26`), and then the orphaned `Localizable.xcstrings` entry (line ~3319 + its 15 translations).

---

## Considered & dismissed (7 refuted — important context)

The verifier **refused to confirm** these, and that judgment is worth recording so they aren't "re-discovered" later:

- **v4 rollback scaffolding is NOT dead code (×3 candidates).** Three finders flagged the hardcoded `useDaybreakPanel = true` / `useV4Settings = true` flags and the "entire legacy panel/settings stack" as dead/deletable. **Refuted:** the legacy `PanelController`/`ParentPanelController`/`PreferencesViewController`/`AppearanceViewController`/storyboard classes have genuine references in the executed test target, in Interface Builder `customClass` bindings (`Preferences.storyboard`, `Panel.xib`, `HourMarkerViewItem.xib`), and in ungated production paths. The flags are a **deliberate, documented emergency-rollback lever** for the v4 beta. Only ~3 statically-unreachable `else`-branch lines are truly dead today. See the next section for the *post-GA* plan.
- **Export-log "world-readable TOCTOU" — not exploitable.** The momentary `0o644` window is inert because every enclosing directory (sandbox container temp and `/var/folders/.../T`) is `0o700`-owned by the user; no other principal can traverse to the file. UUID filenames remove any predictable-path angle. The `0o600` chmod is harmless defense-in-depth, not a load-bearing control with a gap.
- **Settings import "applies attacker JSON" — not a real flaw.** Requires deliberate user file-picker action, grants no capability the one-click toggles don't, toggles only the app's *own* login item, reaches no code-exec/arbitrary-FS sink under the sandbox, and the dangerous deserialization surface (timezone blobs) is already gated by `NSSecureCoding`. Defense-in-depth nicety at most.
- **Force-unwrapped Control Center `URL` — not a crash/security issue.** `ControlCenterSettings.url` is a lazily-evaluated static (only on user click, never at launch), the string is a compile-time constant with no attacker input, and an existing CI test already asserts it parses.
- **"Unbounded" static caches in `TimezoneDataOperations` — effectively bounded.** Keyed by timezone + *today's calendar day* (not the scrubbed slider date), so scrubbing/ticking cannot multiply entries; growth is a few hundred tiny tuples per long session. The genuinely hot Daybreak path uses a *different* cache that is already explicitly bounded to 512 with an `invalidate()`.

---

## SwiftLint summary (79 warnings, 0 errors)

Non-blocking, but several overlap with the findings above. Dominant rules:
- **`identifier_name`** — single-letter locals (`c/f/v/r/g/b/h/m`), heavily in `SettingsManager.swift` decode helpers (~31) and the Daybreak color/geometry code. Cosmetic.
- **`type_body_length`** — `PanelController` (356), `TimezoneAdditionHandler` (347), `AppearanceViewController` (342). The first and third are legacy (kill-switched) classes; revisit during the post-GA cleanup.
- **`cyclomatic_complexity`** ×3 + **`function_body_length`** ×1 — all in `SettingsManager.swift` decode paths (the v1/v2 back-compat import). Candidate for a focused refactor.
- Minor singles: `trailing_comma` ×2, `function_parameter_count` (`DaybreakViewModel` 7, `TimezoneData.make` 6), `blanket_disable_command` ×2 (`DaybreakEngine`), `unneeded_override` (`TimezoneCellView:276`), `large_tuple` (`DaybreakTokens:194`).

No `force_cast`/`force_try` (the two rules configured as **errors**).

---

## Forward-looking: the biggest debt reduction is *post-GA*, by design

The single largest cleanup available is **retiring the v4 rollback scaffolding** once `4.0.0` GA has soaked and is confirmed stable:

- Flip away from / remove the hardcoded `useDaybreakPanel` and `useV4Settings` flags in `AppDelegate.swift`.
- Delete the now-superseded **legacy panel stack** (`PanelController`, `ParentPanelController`, the Modern Slider extensions, `NoTimezoneView`) and **legacy storyboard settings** (`PreferencesViewController`, `AppearanceViewController`, `Preferences.storyboard`) — and their tests (`PreferencesStoryboardTests`, the empty-state regression test).
- This also retires several of the largest SwiftLint offenders (`PanelController`, `AppearanceViewController`) and makes F24/F25 moot.

**Do not do this now.** While in beta, that code is the documented instant-rollback path and is still wired into context menus, the dock menu, the team-accent relaunch flow, and tests. It should be a **single dedicated PR after GA**, with the legacy paths removed atomically and the test target updated. Estimated ~2,000 lines. This is filed as its own tracking issue so it isn't forgotten.

*— End of review. No files were modified. All proposed fixes are unapplied.*
