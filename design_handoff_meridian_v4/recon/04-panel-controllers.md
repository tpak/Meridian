# 04 — Panel Controllers API Cheatsheet

> Read-only recon for v4 UI redesign. No files were modified.
> Source root: `Meridian-v4/Meridian/`

---

## 1. Class Hierarchy

```
NSWindowController
  └── ParentPanelController          // Panel/ParentPanelController.swift
        └── PanelController          // Panel/PanelController.swift
```

`PanelController` is both the **NSWindowController** and the **NSWindowDelegate** for the panel.

---

## 2. Window / Panel Construction

### Instantiation (AppDelegate.swift:10)

```swift
internal lazy var panelController = PanelController(windowNibName: .panel)
// .panel is NSNib.Name("Panel") — defined in Overall App/Foundation + Additions.swift:16
// NIB file: App/en.lproj/Panel.xib
```

The window in `Panel.xib` is a **`CustomPanel: NSPanel`** (not a plain `NSWindow`).

### CustomPanel key overrides (Panel/UI/CustomPanel.swift)

```swift
class CustomPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    // Key equivalents handled by CustomPanel (no IBAction required):
    // Cmd+Q  → NSApplication.shared.terminate(nil)
    // Cmd+,  → panelController.openPreferencesWindow()
    // Cmd+W  → close()
    // Cmd+C  → panelController.copyFirstTimezoneToClipboard()
    // Esc    → close()  (keyCode 53)
}
```

### Window configuration (PanelController.awakeFromNib)

```swift
window?.title = "Meridian Panel"
window?.setAccessibilityIdentifier("Meridian Panel")
window?.isMovableByWindowBackground = false  // overridden in floating mode
window?.acceptsMouseMovedEvents = true
window?.isOpaque = false
window?.backgroundColor = NSColor.clear
```

**Two window modes** set by `applyWindowMode()`:

| Mode | `panel.level` | `collectionBehavior` | `isMovableByWindowBackground` |
|------|--------------|----------------------|-------------------------------|
| Menubar (default) | `.popUpMenu` | `[]` | `false` |
| Floating | `.floating` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | `true` |

Floating mode frame autosave name: `"MeridianFloatingPanel"`.

---

## 3. Show / Hide Flow

### Entry point: status-bar button click

```
NSStatusBarButton.action = #selector(menubarIconClicked(_:))
    → StatusItemHandler.menubarIconClicked(_:)
        → AppDelegate.togglePanel(_ sender: NSButton)
            → panelController.showWindow(nil)
            → panelController.setActivePanel(newValue: sender.state == .on)
```

`AppDelegate.togglePanel` (AppDelegate.swift:317):
```swift
@IBAction open func togglePanel(_ sender: NSButton) {
    panelController.showWindow(nil)
    panelController.setActivePanel(newValue: sender.state == .on)
    NSApp.activate(ignoringOtherApps: true)
}
```

### Global keyboard shortcut path

```swift
// AppDelegate.assignShortcut()
GlobalShortcutMonitor.shared.action = { [weak self] in
    guard let button = self?.statusBarHandler.statusItem.button else { return }
    button.state = button.state == .on ? .off : .on
    self?.togglePanel(button)
}
GlobalShortcutMonitor.shared.register()
```

### Open (PanelController.open)

```swift
func open()
// Called when setActivePanel(newValue: true)
// Resets slider to center, shows/hides modernContainerView,
// calls setPanelFrame() (positions below status-item on non-floating mode),
// starts the 1-second Repeater timer, reloads mainTableView.
```

### Close (PanelController.minimize)

```swift
func minimize()
// Pauses parentTimer, fades window alpha to 0 over 0.1s, then orderOut(nil).
// Sets datasource = nil after hide.
```

### State setter

```swift
func setActivePanel(newValue: Bool)
// hasActivePanel = newValue; routes to open() or minimize()
```

### Lookup from anywhere (class method)

```swift
class func panel() -> PanelController?
// Walks NSApplication.shared.windows, finds windowController is PanelController.
// Used heavily by TimezoneCellView, TimezoneDataSource, SettingsManager.
```

### Resign key → auto-close (NSWindowDelegate)

```swift
func windowDidResignKey(_: Notification)
// Calls setActivePanel(newValue: false) unless isFloatingMode or isShowingContextMenu.
```

---

## 4. Panel Frame Positioning

```swift
private func setPanelFrame()
// Called from open() when not in floating mode.
// Finds the screen containing the status-item button by probing 100pt below
// the status item's origin (PanelLayout.statusItemScreenProbeOffset = 100).
// Then calls positionPanelRelativeToStatusItem(_:_:).

func positionPanelRelativeToStatusItem(_ rect: NSRect, _ maxX: CGFloat)
// Centers panel horizontally under status item.
// Pins right edge to screen.maxX - 10 if it would overflow.
// window?.setFrameTopLeftPoint(NSPoint(x: xPoint, y: yPoint))
// window?.invalidateShadow()
```

Layout constants (private enum `PanelLayout`):

```swift
static let frameYPointOffset: CGFloat = 2
static let minimumSpaceBetweenWindowAndScreenEdge: CGFloat = 10
static let statusItemScreenProbeOffset: CGFloat = 100
static let dragHandleTopAnchor: CGFloat = 6
static let dragHandleHeight: CGFloat = 16
static let pinButtonTrailingMargin: CGFloat = 8
static let pinButtonSize: CGFloat = 22
static let versionLabelTrailingMargin: CGFloat = 34
```

---

## 5. ParentPanelController — IBOutlets

```swift
// Panel/ParentPanelController.swift
@IBOutlet var mainTableView: PanelTableView!
@IBOutlet var stackView: NSStackView!
@IBOutlet var scrollViewHeight: NSLayoutConstraint!
@IBOutlet var settingsButton: NSButton!
@IBOutlet var versionStatusLabel: NSTextField!
@IBOutlet var roundedDateView: NSView!

// Modern Slider outlets
@IBOutlet var modernSlider: NSCollectionView!
@IBOutlet var modernSliderLabel: NSTextField!
@IBOutlet var modernContainerView: ModernSliderContainerView!
@IBOutlet var goBackwardsButton: NSButton!
@IBOutlet var goForwardButton: NSButton!
@IBOutlet var resetModernSliderButton: NSButton!
```

Additional subviews added programmatically in `PanelController`:

```swift
private var pinButton: NSButton?       // pin/unpin floating mode; in footer
private var dragHandleView: PanelDragHandleView?  // top of window, float-mode only
@IBOutlet var backgroundView: BackgroundPanelView!  // draws rounded rect + arrow
```

---

## 6. Data / Timer Plumbing

```swift
// ParentPanelController properties
var cancellables = Set<AnyCancellable>()
var futureSliderValue: Int = 0          // minutes offset from now
var parentTimer: Repeater?              // fires every 1 second on main thread
var datasource: TimezoneDataSource?
var dataStore: DataStoring = DataStore.shared()  // DI-injectable for tests

lazy var timeScrollerViewModel: TimeScrollerViewModel = { ... }()
lazy var oneWindow: OneWindowController? = { ... }()  // lazy Preferences storyboard
```

Timer tick:
```swift
@objc func updateTime()
// Calls updateMenubarDisplay() if menubar timezones exist.
// Then updates each visible TimezoneCellView in-place (no full reload).
```

1-second `Repeater` started inside `startTimer()` → `startWindowTimer()` → `open()`.
Paused in `minimize()`, cancelled in `windowDidResignKey` (non-floating).

---

## 7. Modern Slider (Time Scroller)

### Constants

```swift
struct PanelConstants {
    static let modernSliderPointsInADay = 96   // one item per 15 min
    static let minutesPerSliderPoint    = 15
}
```

### Slider range / total items

```swift
// TimeScrollerViewModel.totalSliderPoints()
// Range preference key: UserDefaultKeys.futureSliderRange (default NSNumber 6)
// Formula: (96 × dayRange × 2) + 1
// Default (6 days): (96 × 6 × 2) + 1 = 1153 items
// Center item: totalSliderPoints / 2
```

### UserDefaults key for range

```swift
UserDefaultKeys.futureSliderRange   // "sliderDayRange" — see Strings.swift
// Observable via:
UserDefaults.standard.publisher(for: \.sliderDayRange)
```

### Show/hide preference

```swift
dataStore.shouldDisplay(.futureSlider)  // UserDefaultKeys pref key
// Observable via: UserDefaults.standard.publisher(for: \.showFutureSlider)
```

### Slider item cell

```swift
class TimeMarkerViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("HourMarkerViewItem")
    // XIB: Panel/UI/HourMarkerViewItem.xib
    // Every 4th item gets constraint.constant = 0 (tall tick); others = 20 (short tick)
}
```

### Key methods

```swift
// ParentPanelController+ModernSlider.swift

func setupModernSliderIfNeccessary()
// Registers cell, configures scroll view, wires boundsDidChange publisher,
// seeds currentCenterSliderItemIndex = totalItems / 2.

@IBAction func goForward(_: NSButton)        // navigates +1 item
@IBAction func goBackward(_: NSButton)       // navigates -1 item
@IBAction func resetModernSlider(_: NSButton)  // animated return to center

func jumpToSliderMinutes(_ minutes: Int)
// Entry point for time-entry from TimezoneCellView double-click.
// Rounds to nearest 15-min mark for visual position, but drives cells from exact minutes.

func collectionViewDidScroll(_ notification: Notification)
// Computes which center item is visible, calls setDefaultDateLabel(_:),
// then setTimezoneDatasourceSlider(sliderValue:) + mainTableView.reloadData().

public func setDefaultDateLabel(_ index: Int) -> Int
// Returns minutesToAdd; updates modernSliderLabel.stringValue.

func applyTeamAccentToSliderControls()
// Reads DataStore.shared().teamAccent.accentColor and applies to
// goBackwardsButton, goForwardButton, resetModernSliderButton.
```

### Slider label and base date

```swift
var closestQuarterTimeRepresentation: Date?
// Set to timeScrollerViewModel.findClosestQuarterTimeApproximation() on panel open.
// Label shows "Time Scroller" when at center; otherwise "MMM d HH:mm" formatted date.
```

### DraggableClipView snap-to-grid

```swift
class DraggableClipView: NSClipView {
    var onDragEnded: (() -> Void)?  // set to snapSliderToCurrentItem() at setup
}
```

---

## 8. TimezoneDataSource

```swift
class TimezoneDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate, PanelTableViewDelegate {
    var timezones: [TimezoneData]
    var sliderValue: Int
    var dataStore: DataStoring

    init(items: [TimezoneData], store: DataStoring)

    func setSlider(value: Int)
    func setItems(items: [TimezoneData])
}
```

Cell identifiers used in `Panel.xib`:
- `"timeZoneCell"` → `TimezoneCellView` (normal row)
- `"addCell"` → `AddTableViewCell` (empty state, one row; tap opens Preferences)

Row height calculation driven by `UserDefaultKeys.userFontSizePreference` (NSNumber):
```swift
func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat
// Base: fontSize == 4 ? 60 : 65
// +8 if sunrise visible and coords present
// +fontSize+15 if DST transition label visible
// +2 if isSystemTimezone
// +(fontSize * 2)
```

---

## 9. TimezoneCellView

```swift
class TimezoneCellView: NSTableCellView {
    // Outlets (all from Panel.xib)
    @IBOutlet var customName: NSTextField!         // place label
    @IBOutlet var relativeDate: NSTextField!       // "Today", "Tomorrow", date string
    @IBOutlet var time: NSTextField!               // current time (editable on double-click)
    @IBOutlet var sunriseSetTime: NSTextField!     // sunrise or sunset time
    @IBOutlet var dstLabel: NSTextField!           // DST transition note
    @IBOutlet var sunriseImage: NSImageView!       // sunrise.fill / sunset.fill SF symbol
    @IBOutlet var currentLocationIndicator: NSImageView!  // location.fill, hidden unless home tz

    var rowNumber: NSInteger = -1
    var timezoneIdentifier: String = ""
    private(set) var isEditingTime: Bool = false   // true during inline time edit

    func setTextColor(color: NSColor)
    func setupLayout()     // layout(with:) calls this — adjusts constraint widths for text
}
```

Layout extension (TimezoneDataSource.swift:218):
```swift
extension TimezoneCellView {
    func layout(with model: TimezoneData)
    // Hides/shows sunriseSetTime + sunriseImage based on DataStore.shared().shouldDisplay(.sunrise)
    // then calls setupLayout()
}
```

Inline time-entry (double-click on cell):
```swift
private func beginTimeEntry()   // makes `time` field editable
private func commitTimeEntry()  // parses text → minutes → calls panelController.jumpToSliderMinutes(_:)
private func cancelTimeEntry()  // restores read-only state
```

Single-click copies `"<label> - <time>"` to NSPasteboard.

---

## 10. Key Actions

### openPreferencesWindow / openPreferences

```swift
// ParentPanelController+Actions.swift
@objc func openPreferencesWindow()
// oneWindow?.openGeneralPane()
// oneWindow is lazy-loaded from Preferences.storyboard's initial controller (OneWindowController)

@objc func openPreferences(_: Any?)
// Responder-chain target for AddTableViewCell "+" button → calls openPreferencesWindow()
```

### copyFirstTimezoneToClipboard

```swift
@objc func copyFirstTimezoneToClipboard()
// Requires mainTableView.numberOfRows > 0
// Gets row 0 as TimezoneCellView
// Copies "<customName.stringValue> - <time.stringValue>" to NSPasteboard.general
// Shows toast: window?.contentView?.makeToast("Copied to Clipboard".localized())
```

### copyAllTimezonesToClipboard

```swift
@objc func copyAllTimezonesToClipboard()
// Maps dataStore.timezoneObjects() through TimezoneDataOperations.time(with: futureSliderValue)
// Joins with " / " separator, copies to pasteboard, shows toast
```

### deleteTimezone

```swift
func deleteTimezone(at row: Int)
// Removes from DataStore, calls updateDefaultPreferences(), posts .customLabelChanged
```

### setTimezoneDatasourceSlider

```swift
func setTimezoneDatasourceSlider(sliderValue: Int)
// futureSliderValue = sliderValue
// datasource?.setSlider(value: sliderValue)
```

### Floating mode toggle

```swift
@objc func toggleFloatingMode()    // DataStore.shared().floatOnTop = !isFloatingMode
// Triggers UserDefaults publisher → applyWindowMode() → updateFloatModeUI()
```

---

## 11. Supporting View Types

```swift
class BackgroundPanelView: NSView
// Draws rounded-rect body + optional arrow pointing up toward status item.
// Corner radius: 8pt, border width: 1pt, arrow height: 4pt.
// Uses NSColor.windowBackgroundColor for fill; allowsVibrancy = true.

class ModernSliderContainerView: NSView
// Tracks mouse enter/exit to set currentlyInFocus: Bool.
// When in focus, updateTime() skips cell updates (user is scrubbing).

class DraggableClipView: NSClipView
// Custom drag-scroll for modernSlider; calls onDragEnded? on mouse-up.

class ThinScroller: NSScroller
// Override: width = 10pt, no knob-slot background drawing.

class PanelDragHandleView: NSView
// Thin strip at top of panel for repositioning in floating mode.
// Hidden in menubar mode.

class PanelTableView: NSTableView
// Adds hover-row tracking via NSTrackingArea.
// protocol PanelTableViewDelegate: NSTableViewDelegate {
//     func tableView(_ table: NSTableView, didHoverOver row: NSInteger)
// }
// hoverRow: Int read-only; -1 when no row hovered.
// Forwards arrow-key events to field editor during inline time-edit.

class NoTimezoneView: NSView
// Shown as tableView background when timezones list is empty.
// Animated 🌏 emoji + "No places added" text.

class AddTableViewCell: NSTableCellView
// Shown for the single row when timezones are empty.
// Contains a "+" button that sends openPreferences: up the responder chain.
```

---

## 12. UserDefaults Keys (relevant to panel)

```swift
// From Overall App/Strings.swift — UserDefaultKeys struct
UserDefaultKeys.futureSliderRange       // "sliderDayRange" — NSNumber, default 6 (days each side)
UserDefaultKeys.showFutureSlider        // Bool preference driving modernContainerView visibility
UserDefaultKeys.userFontSizePreference  // NSNumber (0–4+); affects row height + font size
UserDefaultKeys.relativeDateKey         // NSNumber; 3 = hidden (row height shrinks 5pt)
UserDefaultKeys.betaUpdatesEnabled      // Bool; Sparkle beta channel
UserDefaultKeys.tahoeOnboardingShown    // Bool; one-shot Control Center dialog
UserDefaultKeys.reopenAppearanceOnLaunch // Bool; consumed at launch to jump to Appearance tab
UserDefaultKeys.emptyString             // "" — sentinel for clearing dstLabel / offsets

// KVO-compatible property keys (UserDefaults + KVOExtensions.swift)
\.showFutureSlider    // Bool
\.userFontSize        // Int
\.sliderDayRange      // Int
\.floatOnTop          // Bool
```

---

## 13. TimeScrollerViewModel

```swift
struct TimeScrollerViewModel {
    init(dataStore: DataStoring)

    func totalSliderPoints() -> Int
    // = (96 × sliderDayRange × 2) + 1

    func calculateMinutesToAdd(for index: Int, baseDate: Date, now: Date = Date()) -> (Int, String)
    // Returns (minutesOffset, labelString).
    // Center index → (0, "Time Scroller")
    // Each step = 15 minutes.

    func findClosestQuarterTimeApproximation() -> Date
    // Returns next :00, :15, :30, or :45 boundary after now.

    func timezoneFormattedStringRepresentation(_ date: Date) -> String
    // Format: "MMM d HH:mm" in current timezone/locale.
}
```

---

## 14. AppDelegate Panel Accessors

```swift
// AppDelegate.swift
internal lazy var panelController = PanelController(windowNibName: .panel)

func statusItemForPanel() -> StatusItemHandler
open func setupMenubarTimer()
open func invalidateMenubarTimer(_ showIcon: Bool)

@IBAction open func togglePanel(_ sender: NSButton)
// showWindow(nil), setActivePanel(newValue: sender.state == .on), NSApp.activate

@objc private func openPreferencesWindow()
// panelController.openPreferencesWindow()
```

---

## 15. Injection Points for SwiftUI Root

The cleanest v4 injection points, in order of least disruption:

1. **Replace `Panel.xib` contentView**: Keep `CustomPanel` (its key/main overrides and keyboard shortcuts are needed), keep `PanelController` as the window controller, but replace the XIB's content view with a `NSHostingView<YourSwiftUIRoot>`. All existing show/hide, positioning, and timer plumbing stays intact.

2. **Keep `ParentPanelController` for state**: `futureSliderValue`, `datasource`, `dataStore`, `timeScrollerViewModel`, `parentTimer` are the live-state owners. Either keep them and publish via `ObservableObject`, or extract into a new `PanelViewModel` that both the old NSWindowController and new SwiftUI view can share.

3. **`PanelController.panel()` is called from many places**: `TimezoneCellView`, `TimezoneDataSource`, `SettingsManager`, `AppearanceViewController`. Any SwiftUI replacement must preserve a way to reach the panel controller (or the state it owns) from those call sites.

4. **`TimezoneDataSource` (NSTableViewDelegate) can be deleted**: Once the table is SwiftUI, the datasource, delegate, and `PanelTableViewDelegate` are no longer needed. `futureSliderValue` and `dataStore.timezoneObjects()` are the only inputs a new SwiftUI List needs.

5. **Float-mode UX**: The `DraggableClipView`, `PanelDragHandleView`, and `applyWindowMode()` logic must survive or be ported. Float mode is a user-visible feature gated on `DataStore.shared().floatOnTop` / `UserDefaultKeys` KVO key `\.floatOnTop`.

---

## 16. Gotchas

- `TimezoneCellView.setupTextSize()` **calls `DataStore.shared()` directly** (not DI-injected) because `NSTableView` instantiates cells from XIB outside the DI chain. Any SwiftUI replacement should pass font size as an `EnvironmentValue` or `@AppStorage`.
- `PanelController.panel()` walks all windows at call time — it is **not cached**. Calling it frequently is fine but worth noting.
- The 1-second `Repeater` is started in `open()` and **paused (not stopped)** in `minimize()`. It is fully deallocated in `windowDidResignKey` (non-floating) and `windowWillClose`. Floating-mode panels keep the timer running even when not key.
- `datasource` is set to `nil` in `minimize()`. This releases the data source. It is re-created on every `updateDefaultPreferences()` call in `open()`.
- `modernContainerView.currentlyInFocus` pauses `updateTime()` cell updates while the user scrubs the slider — essential for scroll performance.
- `closestQuarterTimeRepresentation` is the **base date** for all slider label math. It is reset on every `open()` and in `resetModernSlider`. It is the next :00/:15/:30/:45 boundary from the moment the panel opens.
- `window?.contentView?.makeToast(...)` is used for clipboard confirmations — the `Toasty` extension on `NSView` (Panel/UI/Toasty.swift).
