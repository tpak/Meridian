# 03 — Status Item / Menu Bar

Recon for v4 UI redesign. Read-only; no source files were modified.

---

## Ownership

```swift
// AppDelegate.swift
private lazy var statusBarHandler: StatusItemHandler = StatusItemHandler(with: DataStore.shared())
```

`statusBarHandler` is a private lazy stored property on `AppDelegate`. It is force-materialized in `continueUsually()` so the status item appears at a predictable point in the launch sequence:

```swift
func continueUsually() {
    checkIfAppIsAlreadyOpen()
    _ = statusBarHandler          // forces lazy init
    assignShortcut()
    setActivationPolicy()
}
```

Public accessor used by `PanelController` et al.:
```swift
func statusItemForPanel() -> StatusItemHandler   // returns statusBarHandler
func setupMenubarTimer()                         // calls statusBarHandler.setupStatusItem()
func invalidateMenubarTimer(_ showIcon: Bool)    // calls statusBarHandler.invalidateTimer(showIcon:isSyncing:)
```

Global shortcut wires directly into the status item button:
```swift
GlobalShortcutMonitor.shared.action = { [weak self] in
    guard let button = self?.statusBarHandler.statusItem.button else { return }
    button.state = button.state == .on ? .off : .on
    self?.togglePanel(button)
}
```

---

## StatusItemHandler — Class Declaration

```swift
// Preferences/Menu Bar/StatusItemHandler.swift
class StatusItemHandler: NSObject {
    var hasActiveIcon: Bool = false
    var menubarTimer: Timer?
    var statusItem: NSStatusItem   // NSStatusBar.system.statusItem(withLength: .variableLength)
    private var statusContainerView: StatusContainerView?
    private var currentState: MenubarState = .icon   // didSet drives mode transitions
    private let store: DataStore
    private var hasShownBlockedAlertThisSession: Bool = false
    private let visibilityVerificationDelay: TimeInterval = 1.5

    init(with dataStore: DataStore)
}
```

`statusItem` creation (inline lazy var, runs once):
```swift
var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.toolTip = "Meridian"
    (statusItem.button?.cell as? NSButtonCell)?.highlightsBy = NSCell.StyleMask(rawValue: 0)
    return statusItem
}()
```

`autosaveName` is set to `"MeridianStatusItem"` (NSStatusItem.AutosaveName).

---

## MenubarState Enum

```swift
internal enum MenubarState {
    case compactText   // ≥1 favourite timezone exists → show text subviews
    case icon          // no favourites → show clock.fill SF Symbol
}
```

Mode is computed from `store.menubarTimezones().isEmpty`:
```swift
let menubarState: MenubarState = store.menubarTimezones().isEmpty ? .icon : .compactText
```

Switching `currentState` triggers `didSet` which tears down the old mode and builds the new one.

---

## Icon Mode

```swift
private func setMenubarIcon() {
    if statusItem.button?.subviews.isEmpty == false {
        statusItem.button?.subviews = []
    }
    statusItem.button?.title = UserDefaultKeys.emptyString  // ""
    statusItem.button?.image = clockIcon                    // NSImage(systemSymbolName: "clock.fill", ...)
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.toolTip = "Meridian"
}
```

- No attributed string in icon mode; the button title is the empty string constant.
- `statusItem.length` is **not** pinned in icon mode — `variableLength` is restored when leaving compact mode.

---

## Compact Text Mode — Construction Path

```
setupForCompactTextMode()
  └── constructCompactView()
        ├── store.menubarTimezoneObjects()     → [TimezoneData]  (isFavourite == 1)
        ├── StatusContainerView(with:store:bufferContainerWidth:)
        │     └── for each TimezoneData: addTimezone(_:)
        │           └── StatusItemView(frame:) + StatusItemView.dataObject = timezone
        ├── statusItem.button?.addSubview(containerView)
        ├── statusItem.button?.frame = containerView.bounds
        └── statusItem.length = containerView.bounds.size.width   ← PIN: prevents clip
```

After construction, `updateMenubar()` is called to start the timer.

When leaving compact mode back to icon:
```swift
statusItem.button?.subviews = []
statusContainerView = nil
statusItem.length = NSStatusItem.variableLength   // unpin
statusItem.button?.image = nil
```

---

## StatusContainerView — Width Calculation

```swift
// StatusContainerView.swift
class StatusContainerView: NSView {
    init(with timezones: [TimezoneData], store: DataStore, bufferContainerWidth: Int)
    func updateTime()        // calls statusItemViewSetNeedsDisplay() on all subviews
    func addTimezone(_ timezone: TimezoneData)
}
```

Total container width formula (inside `init`):
```swift
let compressedWidth = timezones.reduce(0.0) { result, tz -> CGFloat in
    let precalculatedWidth = Double(compactWidth(for: tz, with: store))
    let ops = TimezoneDataOperations(with: tz, store: store)
    let subtitleSize = compactModeTimeFont.size(for: ops.compactMenuSubtitle(), width: precalculatedWidth, attributes: timeBasedAttributes)
    let titleSize    = compactModeTimeFont.size(for: ops.compactMenuTitle(),    width: precalculatedWidth, attributes: timeBasedAttributes)
    let secondsBuffer: CGFloat = tz.shouldShowSeconds(store.timezoneFormat()) ? 7 : 0
    return result + max(titleSize.width, subtitleSize.width) + bufferWidth + secondsBuffer
}
let calculatedWidth = min(compressedWidth, CGFloat(timezones.count * bufferContainerWidth))
```

`bufferWidth` is a module-level constant:
```swift
let bufferWidth: CGFloat = 9.5
```

Per-timezone width helper (top-level function in StatusContainerView.swift):
```swift
func compactWidth(for timezone: TimezoneData, with store: DataStore) -> Int {
    var totalWidth = 55
    let timeFormat = timezone.timezoneFormat(store.timezoneFormat())

    if store.shouldShowDayInMenubar()  { totalWidth += 12 }

    if timeFormat == DateFormat.twelveHour
    || timeFormat == DateFormat.twelveHourWithSeconds
    || timeFormat == DateFormat.twelveHourWithZero {
        totalWidth += 20
    }
    // twentyFourHour / twentyFourHourWithSeconds → +0

    if timezone.shouldShowSeconds(store.timezoneFormat()) { totalWidth += 15 }
    if store.shouldShowDateInMenubar()                     { totalWidth += 20 }
    return totalWidth
}
```

`bufferCalculatedWidth()` in `StatusItemHandler` computes a per-item upper-bound passed as `bufferContainerWidth`:
```swift
private func bufferCalculatedWidth() -> Int {
    var totalWidth = BufferWidthConstants.baseWidth           // 55
    if store.shouldShowDayInMenubar()                 { totalWidth += 12 }  // BufferWidthConstants.dayBuffer
    if store.isBufferRequiredForTwelveHourFormats()   { totalWidth += 20 }  // .twelveHourBuffer
    if store.shouldShowDateInMenubar()                { totalWidth += 20 }  // .dateBuffer
    return totalWidth
}
```

Width is re-evaluated on every `updateTime()` call via `adjustWidthIfNeccessary()`, which animates a frame change (duration 0.2s, ease-in) if the new width exceeds old width by more than 2pt.

---

## StatusItemView — Text Rendering

```swift
// Preferences/Menu Bar/StatusItemView.swift
class StatusItemView: NSView {
    var dataObject: TimezoneData!   // didSet → initialSetup()

    private let locationView: NSTextField   // label row  (top 35% of 30pt height)
    private let timeView: NSTextField       // time row   (bottom 65%)
}
```

### Fonts
```swift
let compactModeTimeFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
// locationView (label): NSFont.boldSystemFont(ofSize: 10)
// timeView (time):      compactModeTimeFont (monospaced digits, 10pt)
```

### Paragraph style
```swift
let defaultParagraphStyle: NSMutableParagraphStyle = {
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byTruncatingTail
    // English only: lineHeightMultiple = LayoutConstants.englishMenubarLineHeightMultiple (0.92)
    // Other locales: 1.0
}()
```

### Attribute dictionaries (appearance-adaptive, cached per mode)
```swift
// timeAttributes (for timeView)
[.font: compactModeTimeFont,
 .foregroundColor: hasDarkAppearance ? NSColor.white : NSColor.black,
 .backgroundColor: NSColor.clear,
 .paragraphStyle: paragraphStyle]

// textFontAttributes (for locationView)
[.font: NSFont.boldSystemFont(ofSize: 10),
 .foregroundColor: hasDarkAppearance ? NSColor.white : NSColor.black,
 .backgroundColor: NSColor.clear,
 .paragraphStyle: paragraphStyle]
```

Caches are invalidated in `viewDidChangeEffectiveAppearance()`.

### Text content — exact call chain
```swift
// locationView top line ("title"):
locationView.attributedStringValue = NSAttributedString(
    string: operationsObject.compactMenuTitle(),
    attributes: textFontAttributes
)

// timeView bottom line ("subtitle"):
timeView.attributedStringValue = NSAttributedString(
    string: operationsObject.compactMenuSubtitle(),
    attributes: timeAttributes
)
```

---

## compactMenuTitle() and compactMenuSubtitle() — Full Logic

`compactMenuTitle()` (TimezoneDataOperations):
```swift
func compactMenuTitle() -> String {
    // If "show place name in menubar" is OFF, return the label name
    if !store.shouldDisplay(.placeInMenubar) == false {
        return dataObject.formattedTimezoneLabel()  // customLabel ?? formattedAddress ?? timezoneID
    }
    // Otherwise build: [day] [date], or fall back to label if both empty
    var subtitle = ""
    if store.shouldShowDayInMenubar() {
        subtitle.append(date(with: 0, displayType: .menu))  // short weekday "Mon"
    }
    if store.shouldShowDateInMenubar() {
        let d = Date().formatter(with: "MMM d", timeZone: dataObject.timezone())
        subtitle = subtitle.isEmpty ? d : "\(subtitle) \(d)"
    }
    return subtitle.isEmpty ? dataObject.formattedTimezoneLabel() : subtitle
}
```

`compactMenuSubtitle()`:
```swift
func compactMenuSubtitle() -> String {
    // If "show place name in menubar" IS ON, prepend day/date to the time
    var subtitle = ""
    if store.shouldShowDayInMenubar() && store.shouldDisplay(.placeInMenubar) {
        subtitle.append(date(with: 0, displayType: .menu))  // "Mon"
    }
    if store.shouldShowDateInMenubar() && store.shouldDisplay(.placeInMenubar) {
        let d = Date().formatter(with: "MMM d", timeZone: dataObject.timezone())
        subtitle = subtitle.isEmpty ? d : "\(subtitle) \(d)"
    }
    // Always ends with time
    let t = time(with: 0)   // formatted per timezoneFormat()
    subtitle = subtitle.isEmpty ? t : "\(subtitle) \(t)"
    return subtitle
}
```

`time(with:)` delegates to `DateFormatterManager.dateFormatterWithFormat(with:format:timezoneIdentifier:locale:)` using `dataObject.timezoneFormat(store.timezoneFormat())`.

---

## Timer / Refresh Cycle

```swift
@objc func updateMenubar() {
    // calculates next fire date (top of next minute, or next second if seconds shown)
    // invalidates previous timer, creates one-shot non-repeating Timer
    // adds to RunLoop.main with .common mode
    // tolerance: 0.5s (with seconds) or 20s (without)
}

func refresh() {
    if currentState == .compactText {
        updateCompactMenubar()   // → statusContainerView?.updateTime()
        updateMenubar()          // reschedule
    } else {
        setMenubarIcon()
        menubarTimer?.invalidate()
    }
}
```

Timer fires at the top of the next minute (or second). It is **one-shot** (`repeats: false`); each callback reschedules by calling `updateMenubar()` again.

Sleep/wake handling:
- `NSWorkspace.willSleepNotification` → `menubarTimer?.invalidate()`
- `NSWorkspace.didWakeNotification` → `setupStatusItem()` (rebuilds everything)

UserDefaults changes → debounced 250ms → `setupStatusItem()`.

---

## Click → Toggle Panel

```swift
statusItem.button?.action = #selector(menubarIconClicked(_:))
statusItem.button?.target = self

@objc func menubarIconClicked(_ sender: NSStatusBarButton) {
    guard let mainDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
    mainDelegate.togglePanel(sender)
}

// AppDelegate:
@IBAction open func togglePanel(_ sender: NSButton) {
    panelController.showWindow(nil)
    panelController.setActivePanel(newValue: sender.state == .on)
    NSApp.activate(ignoringOtherApps: true)
}
```

Button highlight is suppressed: `highlightsBy = NSCell.StyleMask(rawValue: 0)`.

---

## Favourites — How They Are Read

`menubarTimezones()` / `menubarTimezoneObjects()` on `DataStore` filter the master list by `isFavourite == 1`:

```swift
// DataStore.init / setTimezones(_:)
cachedMenubarTimezones = cachedTimezones.filter {
    TimezoneData.customObject(from: $0)?.isFavourite == 1
}
cachedMenubarTimezoneObjects = cachedMenubarTimezones.compactMap { TimezoneData.customObject(from: $0) }
```

`TimezoneData.isFavourite: Int` — `0` = not a favourite, `1` = favourite (shown in menubar).

---

## UserDefaults Keys Read by the Menubar Pipeline

| Key constant | String value | What it controls |
|---|---|---|
| `UserDefaultKeys.defaultPreferenceKey` | `"defaultPreferences"` | Master timezone list (source of favourites) |
| `UserDefaultKeys.timeFormat` | `"timeFormat"` | Global time format (`TimeFormat` enum, Int raw) |
| `UserDefaultKeys.showDayInMenubar` | `"showDayInMenubar"` | Prepend short weekday ("Mon") |
| `UserDefaultKeys.showDateInMenubar` | `"showDateInMenubar"` | Prepend short date ("Jun 13") |
| `UserDefaultKeys.showPlaceNameInMenubar` | `"showPlaceNameInMenubar"` | Show label on top row vs. day/date |
| `UserDefaultKeys.relativeDateKey` | `"relativeDate"` | Relative day display mode (used by `date(with:displayType:)`) |

All boolean keys use the modernized non-inverted semantics (post-v1 migration).

`isBufferRequiredForTwelveHourFormats()` checks whether `timezoneFormat()` is in the set `{0, 3, 4, 6, 7}` (formats that include AM/PM suffix).

---

## Tahoe / macOS 26 Blocked-Item Detection

```swift
internal enum MenubarBlockDetection {
    static let iconModeMinimumWidth: CGFloat = 20
    static let compactModeMinimumWidth: CGFloat = 40

    static func isStatusItemBlocked(buttonWindowWidth: CGFloat?, isCompactMode: Bool) -> Bool {
        guard let width = buttonWindowWidth else { return true }
        let threshold = isCompactMode ? compactModeMinimumWidth : iconModeMinimumWidth
        return width < threshold
    }
}
```

Checked 1.5 s after `setupStatusItem()` and after `NSApplication.didBecomeActiveNotification`. Shows a blocking `NSAlert` at most once per session (`hasShownBlockedAlertThisSession`). Persistent onboarding flag: `UserDefaultKeys.tahoeOnboardingShown` (`"com.tpak.meridian.tahoeOnboardingShown"`).

---

## Key Enums for v4

### DateFormat (string constants)
```swift
public enum DateFormat {
    static let twelveHour                     = "h:mm a"
    static let twelveHourWithSeconds          = "h:mm:ss a"
    static let twentyFourHour                 = "HH:mm"
    static let twentyFourHourWithSeconds      = "HH:mm:ss"
    static let twelveHourWithZero             = "hh:mm a"
    static let twelveHourWithZeroSeconds      = "hh:mm:ss a"
    static let twelveHourWithoutSuffix        = "hh:mm"
    static let twelveHourWithoutSuffixAndSeconds = "hh:mm:ss"
    static let epochTime                      = "epoch"
}
```

### TimeFormat (UserDefaults-stored, Int rawValue)
```swift
enum TimeFormat: Int {
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
```

### TimezoneData.TimezoneOverride (per-row format override)
```swift
public enum TimezoneOverride: Int {
    case globalFormat = 0
    case twelveHourFormat = 1
    case twentyFourFormat = 2
    case twelveHourWithSeconds = 4
    case twentyHourWithSeconds = 5
    case twelveHourPrecedingZero = 7
    case twelveHourPrecedingZeroSeconds = 8
    case twelveHourWithoutSuffix = 10
    case twelveHourWithoutSuffixAndSeconds = 11
    case epochTime = 12
}
```

---

## v4 Density Preset — Exactly Where to Hook In

The v4 design adds 5 density presets for favourites-in-menubar. The single text-formatting funnel is:

1. **`compactMenuTitle()`** — produces the top (label/day/date) row string.
2. **`compactMenuSubtitle()`** — produces the bottom (time, optionally prefixed with day/date) row string.
3. Both are called in `StatusItemView.statusItemViewSetNeedsDisplay()` and `initialSetup()`.
4. Width is computed in `compactWidth(for:with:)` (top-level function, `StatusContainerView.swift`) and rechecked in `StatusContainerView.adjustWidthIfNeccessary()` after each refresh.

A density preset should control:
- Which combination of `showDayInMenubar` / `showDateInMenubar` / `showPlaceNameInMenubar` is active (these are the three DataStore booleans that gate content in both methods).
- Font size (currently hardcoded `10`pt monospaced/bold — lives in `StatusItemView.swift` globals `compactModeTimeFont` and the `textFontAttributes` computed property).
- Per-item frame height (hardcoded `30`pt in `StatusContainerView.addTimezone(_:)` and `StatusItemView`'s layout constraints).

No attributed string is built anywhere outside `StatusItemView` — all formatting is in those two attribute dictionaries and those two `NSAttributedString(string:attributes:)` calls.
