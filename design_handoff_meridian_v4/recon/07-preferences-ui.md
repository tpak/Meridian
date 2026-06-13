# 07 — Preferences UI Recon

## Overview

The existing Settings window is a **storyboard-based `NSTabViewController`** — NOT
programmatic. The storyboard is `Meridian/Preferences/Preferences.storyboard`.
`OneWindowController` (an `NSWindowController`) is the initial controller; it
holds a `CenteredTabViewController` (subclass of `NSTabViewController`) as its
`contentViewController`.

---

## Window Launch Path

```
AppDelegate.openPreferencesWindow()
  → panelController.openPreferencesWindow()       // ParentPanelController+Actions.swift

ParentPanelController.openPreferencesWindow()
  → oneWindow?.openGeneralPane()                  // opens tab 0

// oneWindow is lazily loaded from the storyboard:
lazy var oneWindow: OneWindowController? = {
    let preferencesStoryboard = NSStoryboard(name: "Preferences", bundle: nil)
    return preferencesStoryboard.instantiateInitialController() as? OneWindowController
}()
```

Secondary launch points:
- `AppDelegate` menu item: `NSMenuItem(title: "Settings", action: #selector(AppDelegate.openPreferencesWindow), keyEquivalent: ",")`
- Panel context menu: `#selector(ParentPanelController.openPreferencesWindow)`
- Panel empty-state "+" button: sends `openPreferences:` up the responder chain → `ParentPanelController.openPreferences(_:)`
- `CustomPanel` edge-tap: `panelController.openPreferencesWindow()`
- Post-relaunch accent restore: `panelController.oneWindow?.openAppearancePane()`

---

## OneWindowController

```swift
class OneWindowController: NSWindowController {
    // Window setup
    private func setupWindow()           // titlebarAppearsTransparent, identifier "Preferences", center
    private func setupToolbarImages()    // SF Symbol template images for tab icons

    // Tab identifier → SF Symbol name map
    private static let identifierToSymbol: [String: String] = [
        "Preferences Tab": "gearshape",
        "Appearance Tab":  "paintbrush",
        "About Tab":       "info.circle"
    ]

    // Public navigation API
    func openGeneralPane()               // tab index 0, NSApp.activate
    func openAppearancePane()            // tab index 1, NSApp.activate

    // Private helper
    private func openPreferenceTab(at index: Int)

    // Accent color observer
    @objc private func refreshToolbarForAccentChange()  // re-runs setupToolbarImages
}
```

Notifications observed:
- `Notification.Name("com.tpak.meridian.accentColorDidChange")` → `refreshToolbarForAccentChange()`

---

## CenteredTabViewController (storyboard custom class)

```swift
class CenteredTabViewController: NSTabViewController {
    override func viewDidLoad() {
        // Localizes each tab's label via NSLocalizedString(identifier, comment:)
        // identifier is the storyboard tabViewItem identifier string
    }
}
```

Tab style: `segmentedControlOnTop` (storyboard attribute).
Transition: `crossfade + slideRight + slideBackward`.

---

## Tab Structure (storyboard)

| Index | Storyboard identifier | Storyboard label | SF Symbol | Controller class |
|-------|-----------------------|------------------|-----------|-----------------|
| 0 | `"Preferences Tab"` | "Time Zones" | `gearshape` | `PreferencesViewController` |
| 1 | `"Appearance Tab"` | " General " | `paintbrush` | `AppearanceViewController` |
| 2 | `"About Tab"` | " About  " | `info.circle` | `AboutViewController` |

Note: storyboard labels ("Time Zones", " General ", " About  ") are overridden at
runtime by `CenteredTabViewController.viewDidLoad` which calls
`NSLocalizedString(identifier, ...)` using the identifier string as the key.

---

## ParentViewController / ParentView

```swift
class ParentViewController: NSViewController {
    var dataStore: DataStoring = DataStore.shared()
    // Sets preferredContentSize = view.frame.size on viewDidLoad
}

class ParentView: NSView {
    override func updateLayer()  // backgroundColor = NSColor.windowBackgroundColor.cgColor
}
```

All three tab controllers inherit from `ParentViewController`.

---

## Tab 0 — General (PreferencesViewController)

**File:** `Preferences/General/PreferencesViewController.swift`

### Key IBOutlets

```swift
@IBOutlet var placeholderLabel: NSTextField!
@IBOutlet var timezoneTableView: NSTableView!        // selected timezones
@IBOutlet var availableTimezoneTableView: NSTableView! // search results (in sheet)
@IBOutlet var timezonePanel: CustomPanel!             // add-timezone sheet
@IBOutlet var progressIndicator: NSProgressIndicator!
@IBOutlet var addButton: NSButton!
@IBOutlet private var recorderControl: ShortcutRecorderButton!
@IBOutlet private var closeButton: NSButton!
@IBOutlet private var timezoneSortButton: NSButton!
@IBOutlet private var timezoneNameSortButton: NSButton!
@IBOutlet private var labelSortButton: NSButton!
@IBOutlet private var deleteButton: NSButton!
@IBOutlet var addTimezoneButton: NSButton!
@IBOutlet var searchField: NSSearchField!
@IBOutlet var messageLabel: NSTextField!
@IBOutlet private var tableview: NSView!             // container for timezoneTableView
@IBOutlet private var additionalSortOptions: NSView! // sort button container
```

### NSTableView columns (timezoneTableView)

Identifiers from `PreferencesDataSourceConstants`:
```swift
struct PreferencesDataSourceConstants {
    static let timezoneNameIdentifier  = "formattedAddress"
    static let customLabelIdentifier   = "label"
    static let availableTimezoneIdentifier = "availableTimezones"
    static let favoriteTimezoneIdentifier  = "favouriteTimezone"  // checkbox column
}
```

Drag type: `NSPasteboard.PasteboardType.dragSession` (custom type).

### Data source / delegate

```swift
// selected list
private var selectionsDataSource: PreferencesDataSource!  // NSTableViewDataSource + Delegate

// search sheet
var searchResultsDataSource: SearchDataSource!
```

### Sorting

```swift
private let sortingManager = TimezoneSortingManager()

// TimezoneSortingManager:
class TimezoneSortingManager {
    enum SortType { case time, label, name }

    func sort(_ timezones: [Data], by type: SortType) -> (sorted: [Data], indicatorImage: NSImage?)
    func sort(_ timezones: [Data], byColumn identifier: String, ascending: inout Bool) -> (sorted: [Data], indicatorImage: NSImage?)
}
```

### Search / addition

```swift
@MainActor
class TimezoneAdditionHandler: NSObject {
    init(host: TimezoneAdditionHost, dataStore: DataStoring = DataStore.shared(),
         geocoder: GeocodingServicing = MapKitGeocodingService())

    func addToFavorites()
    func closePanel()
    func filterArray()
    func selectNewlyInsertedTimezone()
    @objc func search()         // debounced, calls NetworkManager.geocodeAddress async
}
```

`TimezoneAdditionHost` protocol (implemented by PreferencesViewController):
```swift
protocol TimezoneAdditionHost: AnyObject {
    var searchField: NSSearchField! { get }
    var placeholderLabel: NSTextField! { get }
    var availableTimezoneTableView: NSTableView! { get }
    var timezonePanel: CustomPanel! { get }
    var timezoneTableView: NSTableView! { get }
    var messageLabel: NSTextField! { get }
    var addTimezoneButton: NSButton! { get }
    var progressIndicator: NSProgressIndicator! { get }
    var addButton: NSButton! { get }
    var searchResultsDataSource: SearchDataSource! { get }
    func refreshTimezoneTableView(_ shouldSelectNewlyInsertedTimezone: Bool)
    func refreshMainTable()
}
```

### IBActions (tab 0)

```swift
@IBAction func addTimeZone(_: NSButton)          // opens timezonePanel as sheet
@IBAction func addToFavorites(_: NSButton)       // → timezoneAdditionHandler
@IBAction func closePanel(_: NSButton)           // → timezoneAdditionHandler
@IBAction func filterArray(_: Any?)              // → timezoneAdditionHandler
@IBAction func removeFromFavourites(_: NSButton) // removes selected rows from DataStore
@IBAction func sortOptions(_: NSButton)          // toggles additionalSortOptions visibility
@IBAction func sortByTime(_ sender: NSButton)
@IBAction func sortByLabel(_ sender: NSButton)
@IBAction func sortByFormattedAddress(_ sender: NSButton)
```

### Localization strings (tab 0, NSLocalizedString keys)

```swift
"No Timezone Selected"          // error toast
"Max Timezones Selected"        // error toast
"Max Search Characters"         // error toast
"Sort by Time Difference"
"Sort by Name"
"Sort by Label"
"Add Button Title"
"Close Button Title"
"Search Field Placeholder"
```

`.localized()` extension strings (raw text = key):
```
"You're offline, maybe?"
"Try again, maybe?"
"The Internet connection appears to be offline."
```

---

## Tab 1 — Appearance (AppearanceViewController)

**File:** `Preferences/Appearance/AppearanceViewController.swift`

### Key IBOutlets

```swift
@IBOutlet var timeFormat: NSPopUpButton!              // 12 items (incl. 3 disabled separators)
@IBOutlet var theme: NSPopUpButton!                   // Light / Dark / System
@IBOutlet var teamAccentPopup: NSPopUpButton!         // TeamAccent.allCases
@IBOutlet var accentColorInfoButton: NSButton!        // (i) shows AccentColorInfoViewController popover
@IBOutlet var informationLabel: NSTextField!
@IBOutlet var sliderDayRangePopup: NSPopUpButton!
@IBOutlet var visualEffectView: NSVisualEffectView!
@IBOutlet var includeDayInMenubarControl: NSSegmentedControl!   // seg 0=Yes, 1=No
@IBOutlet var includeDateInMenubarControl: NSSegmentedControl!  // seg 0=Yes, 1=No
@IBOutlet var includePlaceNameControl: NSSegmentedControl!      // seg 0=Yes, 1=No
@IBOutlet var appearanceTab: NSTabView!               // inner tab: "Appearance" + "Misc"
@IBOutlet var appDisplayControl: NSSegmentedControl!  // 0=Menubar only, 1=Dock+Menubar
@IBOutlet var floatOnTopControl: NSSegmentedControl!  // 0=Yes, 1=No
@IBOutlet var floatOnTopLabel: NSTextField!
@IBOutlet var sunriseControl: NSSegmentedControl!     // 0=Yes, 1=No (issue #97)
@IBOutlet var futureSliderControl: NSSegmentedControl! // 0=Show, 1=Hide
@IBOutlet var previewPanelTableView: NSTableView!     // 1-row live preview
// Label outlets (all set via .localized() in setup())
@IBOutlet var timeFormatLabel: NSTextField!
@IBOutlet var panelTheme: NSTextField!
@IBOutlet var dayDisplayOptionsLabel: NSTextField!
@IBOutlet var showSliderLabel: NSTextField!
@IBOutlet var showSunriseLabel: NSTextField!
@IBOutlet var largerTextLabel: NSTextField!
@IBOutlet var futureSliderRangeLabel: NSTextField!
@IBOutlet var includeDateLabel: NSTextField!
@IBOutlet var includeDayLabel: NSTextField!
@IBOutlet var includePlaceLabel: NSTextField!
@IBOutlet var appDisplayLabel: NSTextField!
@IBOutlet var previewLabel: NSTextField!
@IBOutlet var miscelleaneousLabel: NSTextField!
@IBOutlet var accentColorLabel: NSTextField!
```

Inner tab view (inside AppearanceViewController's view):
- index 0: "Appearance" (time format, theme, accent, day display options, slider, sunrise, preview)
- index 1: "Misc" (app display options, float on top, future slider range, menubar options)

### Time format popup items

```swift
// Indices 2, 5, 8 are disabled separator items
private static let sliderDayValues = [1, 2, 3, 4, 5, 6, 7, 14, 30, 90]

// timeFormat popup titles (index → TimeFormat raw value):
// 0  → .twelveHour              "h:mm a (7:08 PM)"
// 1  → .twentyFourHour          "HH:mm (19:08)"
// 2  → disabled separator       "-- With Seconds --"
// 3  → .twelveHourWithSeconds   "h:mm:ss a (7:08:09 PM)"
// 4  → .twentyFourHourWithSeconds "HH:mm:ss (19:08:09)"
// 5  → disabled separator       "-- 12 Hour with Preceding 0 --"
// 6  → .twelveHourWithLeadingZero "hh:mm a (07:08 PM)"
// 7  → .twelveHourWithLeadingZeroAndSeconds "hh:mm:ss a (07:08:09 PM)"
// 8  → disabled separator       "-- 12 Hour w/o AM/PM --"
// 9  → .twelveHourWithoutAmPm   "hh:mm (07:08)"
// 10 → .twelveHourWithoutAmPmAndSeconds "hh:mm:ss (07:08:09)"
// 11 → .epoch                   "Epoch Time"
```

### IBActions (tab 1)

```swift
@IBAction func timeFormatSelectionChanged(_ sender: NSPopUpButton)
    // DataStore.shared().timeFormat = TimeFormat(rawValue: index) ?? .twelveHour

@IBAction func teamAccentChanged(_ sender: NSPopUpButton)
    // DataStore.shared().teamAccent = TeamAccent.allCases[index]
    // NSApp.mer_invalidateAccentEverywhere()
    // promptForRestart(applying:) — shows NSAlert, may relaunch app

@IBAction func showAccentColorInfo(_ sender: NSButton)
    // toggles accentInfoPopover (AccentColorInfoViewController)

@IBAction func themeChanged(_ sender: NSPopUpButton)

@IBAction func changeRelativeDayDisplay(_ sender: NSSegmentedControl)

@IBAction func showFutureSlider(_ sender: NSSegmentedControl)
    // DataStore.shared().showFutureSlider = sender.selectedSegment == 0

@IBAction func showSunriseSunset(_ sender: NSSegmentedControl)
    // DataStore.shared().showSunriseSunset = sender.selectedSegment == 0 (enabled)

@IBAction func changeAppDisplayOptions(_ sender: NSSegmentedControl)
    // seg 0 → .menubarOnly, seg 1 → .menubarAndDock
    // NSApp.setActivationPolicy(.accessory / .regular)

@IBAction func floatOnTopChanged(_ sender: NSSegmentedControl)
    // DataStore.shared().floatOnTop = sender.selectedSegment == 0

@IBAction func displayDayInMenubarAction(_ sender: NSSegmentedControl)
    // DataStore.shared().showDayInMenubar = sender.selectedSegment == 0

@IBAction func displayDateInMenubarAction(_ sender: NSSegmentedControl)
    // DataStore.shared().showDateInMenubar = sender.selectedSegment == 0

@IBAction func displayPlaceInMenubarAction(_ sender: NSSegmentedControl)
    // DataStore.shared().showPlaceNameInMenubar = sender.selectedSegment == 0

@IBAction func fontSliderChanged(_: Any)
    // reloads previewPanelTableView only

@IBAction func sliderDayRangeChanged(_ sender: NSPopUpButton)
    // UserDefaults.standard.set(dayValue, forKey: UserDefaultKeys.futureSliderRange)
```

### Restart-to-apply accent flow

```swift
// 1. User changes teamAccentPopup
// 2. DataStore.shared().teamAccent = team
// 3. NSApp.mer_invalidateAccentEverywhere()  → posts .accentColorDidChange
// 4. promptForRestart(applying:) — NSAlert with "Restart Now" / "Apply at Next Launch"
// 5. On "Restart Now":
//    UserDefaults.standard.set(true, forKey: UserDefaultKeys.reopenAppearanceOnLaunch)
//    Process() runs /usr/bin/open -n <bundlePath>
//    DispatchQueue.main.asyncAfter(0.2s) { NSApp.terminate(nil) }
// 6. AppDelegate on next launch checks reopenAppearanceOnLaunch and calls openAppearancePane()
```

Key: `UserDefaultKeys.reopenAppearanceOnLaunch = "com.tpak.meridian.reopenAppearanceOnLaunch"`

### Accent popover controller

```swift
final class AccentColorInfoViewController: NSViewController {
    private static let popoverWidth: CGFloat = 340
    private static let edgePadding: CGFloat = 16
    static let titleText = "About these colors"   // .localized() lookup key
    static let bodyText = "Meridian is an independent project..."  // fan-attribution disclaimer
    // loadView() builds NSStackView with title + wrapping body label, no storyboard
}
```

### Localization strings (tab 1, `.localized()` keys)

```
"Favourite a timezone to enable menubar display options."
"About accent colors"
"About these colors"
"Time Format"
"Panel Theme"
"Accent Color"
"Day Display Options"
"Time Scroller"
"Show Sunrise/Sunset"
"Larger Text"
"Future Slider Range"
"Include Date"
"Include Day"
"Include Place Name"
"Preview"
"Miscellaneous"
"Float on Top"
"Show Meridian in"
```

---

## Tab 2 — About (AboutViewController + AboutView)

**File:** `Preferences/About/AboutViewController.swift` + `Preferences/About/AboutView.swift`

### Hosting pattern

```swift
class AboutViewController: ParentViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
```

### AboutView (SwiftUI)

```swift
struct AboutView: View {
    // Version string: "<CFBundleDisplayName> <CFBundleShortVersionString>"
    private let versionString: String

    @AppStorage(UserDefaultKeys.startAtLogin) private var startAtLogin = false
    private let startupManager = StartupManager()

    // Update interval constants
    fileprivate static let updateIntervalValues: [TimeInterval] = [86400, 604800, 2592000]
    fileprivate static let updateIntervalLabels = ["Daily", "Weekly", "Monthly"]
}
```

Subviews (all private SwiftUI structs):

```swift
private struct AutoUpdateToggle: View
    // @State private var autoUpdate: Bool
    // @State private var lastCheckDate: Date?
    // reads/writes: appDelegate.updaterController.updater.automaticallyDownloadsUpdates
    // reads: appDelegate.updaterController.updater.lastUpdateCheckDate
    // Toggle: "Automatically download and install updates"
    // accessibilityIdentifier: "AutoUpdate"

private struct UpdateCheckControls: View
    // @State private var selectedIndex: Int  (maps to updateIntervalValues)
    // Picker + "Check Now" button
    // writes: appDelegate.updaterController.updater.updateCheckInterval

private struct BetaChannelToggle: View
    // @AppStorage(UserDefaultKeys.betaUpdatesEnabled) private var receiveBetas = false
    // Toggle: "Receive beta releases"
    // accessibilityIdentifier: "ReceiveBetaReleases"
    // onChange: appDelegate.updaterController.updater.checkForUpdateInformation()

private struct SettingsBackupSection: View
    // Button "Export Settings…" → SettingsManager.exportSettings()
    // Button "Import Settings…" → SettingsManager.importSettings()

private struct DebugLoggingSection: View
    // @AppStorage(UserDefaultKeys.debugLoggingEnabled) private var debugLogging = false
    // Toggle: "Enable Debug Logging"
    // conditional Button "Export Log" → Logger.exportLog(to:) + NSWorkspace reveal
```

### AboutView constants

```swift
struct AboutUsConstants {
    static let GitHubURL       = "https://github.com/tpak/Meridian"
    static let GitHubIssuesURL = "https://github.com/tpak/Meridian/issues"
    static let AppStoreLink    = "https://github.com/tpak/Meridian"  // same as GitHubURL
    static let FAQsLink        = "https://github.com/tpak/Meridian/wiki"
}
```

### Localization in AboutView

Mix of `.localized()` extension (AppKit-style) and `String(localized:)` (SwiftUI-style):
```swift
// .localized() (key = raw string, looked up in Localizable.xcstrings):
"Feedback is always welcome:"
"Can't see Meridian in your menu bar?"

// String(localized:):
"Start at Login"
"Automatically download and install updates"
"Last checked: Never"
"Last checked: \(date)"
"Check Now"
"Receive beta releases"
"Pre-release releases — may have bugs."
"Export Settings…"
"Import Settings…"
"Enable Debug Logging"
"Export Log"
"Check for Updates"
```

### Accessibility identifiers

```
"MeridianVersion"     — version Text
"MeridianPrivateFeedback" — GitHub issues link
"MenubarTroubleshooting"  — Control Center link
"StartAtLogin"        — start at login Toggle
"AutoUpdate"          — auto-update Toggle
"ReceiveBetaReleases" — beta channel Toggle
"ExportSettings"      — export Button
"ImportSettings"      — import Button
"DebugLogging"        — debug logging Toggle
```

---

## DataStore Typed Accessors (used by Preferences tabs)

All on `DataStore.shared()`:

```swift
// Protocol DataStoring (injectable in tests via DataStore.shared())
func timezones() -> [Data]
func setTimezones(_ timezones: [Data]?)
func menubarTimezones() -> [Data]
func timezoneObjects() -> [TimezoneData]
func menubarTimezoneObjects() -> [TimezoneData]
func retrieve(key: String) -> Any?
func timezoneFormat() -> NSNumber
func isBufferRequiredForTwelveHourFormats() -> Bool
func shouldShowDateInMenubar() -> Bool
func shouldShowDayInMenubar() -> Bool
func shouldDisplay(_ type: ViewType) -> Bool

// Typed var accessors (on DataStore concrete type):
var timeFormat: TimeFormat            // get/set → UserDefaultKeys.timeFormat
var teamAccent: TeamAccent            // get/set → UserDefaultKeys.teamAccent
var appPresentation: AppPresentation  // get/set → UserDefaultKeys.appDisplayOptions
var floatOnTop: Bool                  // get/set → UserDefaultKeys.floatOnTop
var showSunriseSunset: Bool           // get/set → UserDefaultKeys.showSunriseSunset
var showFutureSlider: Bool            // get/set → UserDefaultKeys.showFutureSlider
var showDayInMenubar: Bool            // get/set → UserDefaultKeys.showDayInMenubar
var showDateInMenubar: Bool           // get/set → UserDefaultKeys.showDateInMenubar
var showPlaceNameInMenubar: Bool      // get/set → UserDefaultKeys.showPlaceNameInMenubar
var theme: Theme                      // get/set
var relativeDateDisplay: RelativeDateDisplay  // get/set
```

---

## Enums (all relevant to Preferences)

```swift
enum TimeFormat: Int, Codable, CaseIterable {
    case twelveHour = 0
    case twentyFourHour = 1
    case twelveHourWithSeconds = 3
    case twentyFourHourWithSeconds = 4
    case twelveHourWithLeadingZero = 6
    case twelveHourWithLeadingZeroAndSeconds = 7
    case twelveHourWithoutAmPm = 9
    case twelveHourWithoutAmPmAndSeconds = 10
    case epoch = 11
}

enum Theme: Int, Codable, CaseIterable {
    case light = 0; case dark = 1; case system = 2
}

enum RelativeDateDisplay: Int, Codable, CaseIterable {
    case relative = 0; case actual = 1; case date = 2; case hidden = 3
}

enum AppPresentation: Int, Codable, CaseIterable {
    case menubarOnly = 0; case menubarAndDock = 1
}

enum TeamAccent: String, Codable, CaseIterable {
    case alpine, astonMartin, audi, cadillac, ferrari, haas,
         mclaren, mercedes, racingBulls, redBull, williams
    var displayName: String   // e.g. "Aston Martin", "Racing Bulls", "Red Bull Racing"
    var accentColor: NSColor
}

enum ViewType {
    case futureSlider, twelveHour, sunrise, showAppInForeground,
         appDisplayOptions, dateInMenubar, placeInMenubar, dayInMenubar
}
```

---

## UserDefaultKeys (Preferences-relevant)

```swift
// From Strings.swift
UserDefaultKeys.startAtLogin              = "startAtLogin"
UserDefaultKeys.timeFormat                = "timeFormat"               // typed Int
UserDefaultKeys.themeKey                  = "defaultTheme"
UserDefaultKeys.showSunriseSunset         = "showSunriseSunset"
UserDefaultKeys.showFutureSlider          = "showFutureSlider"
UserDefaultKeys.showDayInMenubar          = "showDayInMenubar"
UserDefaultKeys.showDateInMenubar         = "showDateInMenubar"
UserDefaultKeys.showPlaceNameInMenubar    = "showPlaceNameInMenubar"
UserDefaultKeys.floatOnTop                = "floatOnTop"
UserDefaultKeys.appDisplayOptions         = "com.tpak.meridian.appDisplayOptions"
UserDefaultKeys.futureSliderRange         = "sliderDayRange"           // Int day count
UserDefaultKeys.userFontSizePreference    = "userFontSize"
UserDefaultKeys.teamAccent                = "com.tpak.meridian.teamAccent"  // String rawValue
UserDefaultKeys.betaUpdatesEnabled        = "com.tpak.meridian.betaUpdatesEnabled"
UserDefaultKeys.debugLoggingEnabled       = "com.tpak.meridian.debugLoggingEnabled"
UserDefaultKeys.reopenAppearanceOnLaunch  = "com.tpak.meridian.reopenAppearanceOnLaunch"
UserDefaultKeys.defaultPreferenceKey      = "defaultPreferences"       // [Data] timezone list
```

---

## Notifications

```swift
Notification.Name("com.tpak.meridian.accentColorDidChange")  // static let in AccentColorSwizzler.swift
Notification.Name.customLabelChanged   // posted when a timezone label is edited
```

`NSApp.mer_invalidateAccentEverywhere()` posts `.accentColorDidChange`.

---

## v4 Rebuild Notes

### What to replace with NavigationSplitView

The 3-tab NSTabViewController maps directly to a `NavigationSplitView` sidebar with
3 items: **Timezones** (was "Preferences Tab"), **Appearance** (was "Appearance Tab"),
**About** (was "About Tab").

### AboutView already SwiftUI — reuse directly

`AboutView` is a clean SwiftUI struct. Host it as-is in a SwiftUI `NavigationSplitView`
detail pane — drop the `AboutViewController` wrapper.

### AppStorage keys for v4 SwiftUI toggles

Use `@AppStorage` with the exact key strings from `UserDefaultKeys`:
```swift
@AppStorage("startAtLogin") var startAtLogin = false
@AppStorage("com.tpak.meridian.betaUpdatesEnabled") var betaUpdatesEnabled = false
@AppStorage("com.tpak.meridian.debugLoggingEnabled") var debugLoggingEnabled = false
@AppStorage("showSunriseSunset") var showSunriseSunset = false
@AppStorage("showFutureSlider") var showFutureSlider = false
@AppStorage("floatOnTop") var floatOnTop = false
@AppStorage("showDayInMenubar") var showDayInMenubar = false
@AppStorage("showDateInMenubar") var showDateInMenubar = false
@AppStorage("showPlaceNameInMenubar") var showPlaceNameInMenubar = false
// timeFormat / teamAccent / appPresentation need RawRepresentable conformance or
// bridge through DataStore.shared() — @AppStorage doesn't natively handle non-Int enums
```

### Panel refresh after settings changes

Many IBActions call:
```swift
PanelController.panel()?.updateDefaultPreferences()
PanelController.panel()?.updateTableContent()
(NSApplication.shared.delegate as? AppDelegate)?.setupMenubarTimer()
```
v4 should use a Combine publisher or `NotificationCenter` post to decouple settings
changes from panel refresh, rather than calling PanelController directly.

### Gotchas

- **Segmented controls use 0=Yes, 1=No** convention throughout Appearance. Ensure
  SwiftUI Toggles respect this mapping when reading/writing.
- **TimeFormat raw values are not contiguous** (0,1,3,4,6,7,9,10,11 — no 2,5,8).
  The popup index ≠ TimeFormat raw value. Use `TimeFormat(rawValue:)`.
- **teamAccent restart dance**: changing accent requires a relaunch to apply AppKit
  controls. v4 SwiftUI may handle this differently — test whether the same limitation
  applies to SwiftUI controls.
- **futureSliderRange stores a day count** (Int), not an index. The popup index maps
  to `sliderDayValues = [1,2,3,4,5,6,7,14,30,90]`.
- **`PreferencesDataSourceConstants.favoriteTimezoneIdentifier = "favouriteTimezone"`**
  (British spelling) — match exactly in any v4 list that serializes isFavourite.
- **DataStore.shared()** is not `@MainActor`; safe to call from main but not thread-safe
  from background tasks.
