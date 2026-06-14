# 05 — AppDelegate Lifecycle

Source file: `Meridian/AppDelegate.swift`
Related: `GlobalShortcutMonitor.swift`, `StatusItemHandler.swift`, `AccentColorSwizzler.swift`, `Strings.swift`

---

## Entry Point

```swift
@main
open class AppDelegate: NSObject, NSApplicationDelegate {
    internal lazy var panelController = PanelController(windowNibName: .panel)
    private lazy var statusBarHandler: StatusItemHandler = StatusItemHandler(with: DataStore.shared())
    lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }()
}
```

`@main` — this is the process entry point. `panelController` and `statusBarHandler` are lazy; their materialization order matters (see below).

---

## `applicationDidFinishLaunching` Sequence

```swift
public func applicationDidFinishLaunching(_: Notification) {
    AppDefaults.initialize(with: DataStore.shared(), defaults: UserDefaults.standard)
    AccentColorSwizzler.install()          // swizzles NSColor.controlAccentColor once
    logLaunch()
    sentinelTask = Task.detached(priority: .utility) {
        self.checkForPreviousUncleanExit()
        self.writeSentinelFile()
    }
    enableAutoUpdateByDefault()
    backfillMissingCoordinates()
    continueUsually()                      // forces statusBarHandler, registers shortcut, sets activation policy
    setupMemoryPressureMonitoring()
    reopenAppearanceIfRelaunchedForTeamAccent()
    showTahoeOnboardingIfNeeded()
    observeAppActivationForVisibilityRecheck()
}
```

**`continueUsually()`** is the critical sequencing step:

```swift
func continueUsually() {
    checkIfAppIsAlreadyOpen()    // kills duplicate instances
    _ = statusBarHandler         // forces the lazy var → NSStatusItem appears now
    UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
    assignShortcut()
    setActivationPolicy()
}
```

---

## Activation Policy (Dock vs Menubar-only)

**Info.plist**: `LSUIElement = true` — the process starts as an agent (no Dock icon, no App menu) regardless of user pref.

**Runtime override** in `continueUsually()`:

```swift
private func setActivationPolicy() {
    let activationPolicy: NSApplication.ActivationPolicy =
        DataStore.shared().appPresentation == .menubarOnly ? .accessory : .regular
    if currentActivationPolicy != activationPolicy {
        NSApp.setActivationPolicy(activationPolicy)
    }
}
```

```swift
enum AppPresentation: Int, Codable, CaseIterable {
    case menubarOnly     = 0   // .accessory — no Dock icon
    case menubarAndDock  = 1   // .regular   — Dock icon shown
}

// UserDefaults key:
UserDefaultKeys.appDisplayOptions  // "com.tpak.meridian.appDisplayOptions"
// DataStore accessor:
DataStore.shared().appPresentation: AppPresentation  // get/set
```

**"Hide from Dock" action** (available in the dock context menu when in `.regular` mode):

```swift
@objc func hideFromDock() {
    DataStore.shared().appPresentation = .menubarOnly
    NSApp.setActivationPolicy(.accessory)
}
```

**Gotcha**: `LSUIElement=true` means a fresh install starts in `.accessory` mode even if `appPresentation == .menubarAndDock` — `setActivationPolicy()` corrects this at every launch.

---

## Status Item Setup

```swift
private lazy var statusBarHandler: StatusItemHandler = StatusItemHandler(with: DataStore.shared())

// Public accessors from AppDelegate:
func statusItemForPanel() -> StatusItemHandler              // returns statusBarHandler
open func setupMenubarTimer()                               // calls statusBarHandler.setupStatusItem()
open func invalidateMenubarTimer(_ showIcon: Bool)          // calls statusBarHandler.invalidateTimer(showIcon:isSyncing:)
```

`StatusItemHandler.init(with:)` calls `setupStatusItem()` and `setupNotificationObservers()`. The status item itself:

```swift
var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.toolTip = "Meridian"
    return statusItem
}()
```

Two menubar states, controlled by `currentState: MenubarState`:

```swift
internal enum MenubarState {
    case compactText   // one or more "favourite" timezones shown as text
    case icon          // clock.fill SF Symbol only
}
```

State is `.compactText` if `store.menubarTimezones()` is non-empty, otherwise `.icon`.

---

## Global Keyboard Shortcut

```swift
// Singleton
final class GlobalShortcutMonitor {
    static let shared = GlobalShortcutMonitor()

    struct KeyCombo: Codable, Equatable {
        let keyCode: UInt16
        let modifierFlags: UInt   // NSEvent.ModifierFlags.rawValue
        var displayString: String { … }
    }

    var action: (() -> Void)?
    var currentShortcut: KeyCombo? { get set }   // persisted to UserDefaults

    func register()    // installs global + local NSEvent monitors
    func unregister()  // removes them
}
```

UserDefaults keys used by `GlobalShortcutMonitor`:
- Current format: `"globalPing"` (stored as `Data` via `JSONEncoder`)
- Legacy format (auto-migrated on first read): `"values.globalPing"` (`[String: Any]` dict)

**Wired in AppDelegate:**

```swift
private func assignShortcut() {
    GlobalShortcutMonitor.shared.action = { [weak self] in
        guard let button = self?.statusBarHandler.statusItem.button else { return }
        button.state = button.state == .on ? .off : .on
        self?.togglePanel(button)
    }
    GlobalShortcutMonitor.shared.register()
}
```

**Toggle panel action** (also the target of the status item button click):

```swift
@IBAction open func togglePanel(_ sender: NSButton) {
    panelController.showWindow(nil)
    panelController.setActivePanel(newValue: sender.state == .on)
    NSApp.activate(ignoringOtherApps: true)
}
```

---

## Preferences Window Presentation

```swift
// In AppDelegate dock menu and keyboard shortcut:
@objc private func openPreferencesWindow() {
    panelController.openPreferencesWindow()    // → ParentPanelController+Actions.swift
}

// ParentPanelController+Actions.swift:
@objc func openPreferencesWindow() {
    oneWindow?.openGeneralPane()               // opens tab index 0
}

// ParentPanelController.swift:
lazy var oneWindow: OneWindowController? = {
    preferencesStoryboard.instantiateInitialController() as? OneWindowController
}()
```

`OneWindowController` public surface (called from AppDelegate/PanelController):

```swift
class OneWindowController: NSWindowController {
    func openGeneralPane()     // tab index 0 — General/Timezones
    func openAppearancePane()  // tab index 1 — Appearance (accent picker, etc.)
    // private:
    private func openPreferenceTab(at index: Int)
}
```

**Reopen Appearance after team-accent relaunch:**

```swift
private func reopenAppearanceIfRelaunchedForTeamAccent() {
    guard UserDefaults.standard.bool(forKey: UserDefaultKeys.reopenAppearanceOnLaunch) else { return }
    UserDefaults.standard.removeObject(forKey: UserDefaultKeys.reopenAppearanceOnLaunch)
    DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.openAppearanceAfterRelaunch) { [weak self] in
        self?.panelController.oneWindow?.openAppearancePane()
    }
}
// UserDefaultKeys.reopenAppearanceOnLaunch = "com.tpak.meridian.reopenAppearanceOnLaunch"
// TimingConstants.openAppearanceAfterRelaunch: TimeInterval = 0.3
```

---

## Sparkle / Auto-Update

```swift
extension AppDelegate: SPUUpdaterDelegate {

    // Immediate install for menubar apps (no persistent quit → updates would stall):
    public func updater(_: SPUUpdater,
                        willInstallUpdateOnQuit item: SUAppcastItem,
                        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }

    // Beta channel opt-in:
    public func allowedChannels(for _: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: UserDefaultKeys.betaUpdatesEnabled) ? ["beta"] : []
    }
    // UserDefaultKeys.betaUpdatesEnabled = "com.tpak.meridian.betaUpdatesEnabled"
}
```

`allowedChannels` returns `["beta"]` when the user has opted in. Stable users get `[]` (default channel only). Stable GA items have no channel tag and are always visible to all users; beta items carry `<sparkle:channel>beta</sparkle:channel>`.

Auto-update defaults are set once per install:

```swift
private func enableAutoUpdateByDefault() {
    // One-time flag: "HasSetAutoUpdateDefault"
    updaterController.updater.automaticallyChecksForUpdates = true
    updaterController.updater.automaticallyDownloadsUpdates = true
    // Migration flag: "HasFixedAutoUpdateSync" — syncs downloads → checks
}
```

---

## App-wide Notification Observers

| Observer | Registered in | Notification | Action |
|---|---|---|---|
| `NSApplication.didBecomeActiveNotification` | `AppDelegate.observeAppActivationForVisibilityRecheck()` | `NSApplication.didBecomeActiveNotification` | `statusBarHandler.scheduleVisibilityVerification()` |
| Interface style change | `StatusItemHandler.setupNotificationObservers()` | `DistributedNotificationCenter` `.interfaceStyleDidChange` (`"AppleInterfaceThemeChangedNotification"`) | `respondToInterfaceStyleChange()` → `updateCompactMenubar()` |
| UserDefaults changed | `StatusItemHandler.setupNotificationObservers()` | `UserDefaults.didChangeNotification` (debounced 250ms) | `setupStatusItem()` |
| Wake from sleep | `StatusItemHandler.setupNotificationObservers()` | `NSWorkspace.didWakeNotification` | `setupStatusItem()` |
| Will sleep | `StatusItemHandler.setupNotificationObservers()` | `NSWorkspace.willSleepNotification` | `menubarTimer?.invalidate()` |
| System timezone change | `ParentPanelController.windowDidLoad()` | `NSNotification.Name.NSSystemTimeZoneDidChange` | `systemTimezoneDidChange()` |
| Accent color changed | `PanelController.setupAccentColorObserver()` | `.accentColorDidChange` (`"com.tpak.meridian.accentColorDidChange"`) | `accentColorDidChange()` → redraw slider/pin button |
| Accent color changed | `OneWindowController.windowDidLoad()` | `.accentColorDidChange` | `refreshToolbarForAccentChange()` → `setupToolbarImages()` |

The `.interfaceStyleDidChange` name:

```swift
// Overall App/Foundation + Additions.swift
extension NSNotification.Name {
    static let interfaceStyleDidChange = NSNotification.Name("AppleInterfaceThemeChangedNotification")
}
```

---

## AccentColor Swizzle

```swift
enum AccentColorSwizzler {
    static func install()   // idempotent; called once in applicationDidFinishLaunching
}
// Swaps NSColor.controlAccentColor → NSColor.mer_currentTeamAccentColor()
// which returns DataStore.shared().teamAccent.accentColor

// Invalidation (posts accentColorDidChange, does NOT attempt AppKit cache flush):
extension NSApplication {
    func mer_invalidateAccentEverywhere()
    // → NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
}
```

**Gotcha**: AppKit caches `NSDynamicSystemColor` resolutions. Swizzling alone is insufficient; the only fully-reliable way to repaint all AppKit surfaces is to relaunch. `AppearanceViewController` offers a "Restart Now" prompt when the user changes the team. Surfaces explicitly managed by Meridian code (panel slider, pin button, toolbar icons) repaint via the `.accentColorDidChange` observer.

---

## Crash Sentinel

Written on launch, deleted on clean `applicationWillTerminate`. Path:

```
~/Library/Application Support/Meridian/.running
```

Content: ISO 8601 launch timestamp. On next launch, if the file is present, logs `"Previous session exited uncleanly"`. All sentinel work runs on a `Task.detached(priority: .utility)` to avoid blocking the main thread.

---

## Tahoe Menubar Onboarding (issue #125)

macOS Tahoe silently classifies new NSStatusItems as `.ephemeral` until the user enables them in Control Center.

```swift
// One-time onboarding alert — shown only if flag not yet set:
UserDefaultKeys.tahoeOnboardingShown  // "com.tpak.meridian.tahoeOnboardingShown"

// Recovery alert (StatusItemHandler) — shown once per process session if
// the status item's button window width is below threshold:
internal enum MenubarBlockDetection {
    static let iconModeMinimumWidth:    CGFloat = 20
    static let compactModeMinimumWidth: CGFloat = 40
    static func isStatusItemBlocked(buttonWindowWidth: CGFloat?, isCompactMode: Bool) -> Bool
}

// Deep-link to System Settings → Control Center:
internal enum ControlCenterSettings {
    static let urlString = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
    static func open()
}
```

Visibility re-check is also triggered whenever the app becomes active (`NSApplication.didBecomeActiveNotification`), so returning from System Settings re-runs the heuristic.

---

## Dock Menu

```swift
public func applicationDockMenu(_: NSApplication) -> NSMenu? {
    // Items: "Toggle Panel", "Settings" (⌘,), "Check for Updates…", "Hide from Dock"
    // checkForUpdates target is updaterController (SPUStandardUpdaterController)
    // hideFromDock sets appPresentation = .menubarOnly and NSApp.setActivationPolicy(.accessory)
}
```

---

## Key UserDefaults Constants (AppDelegate-relevant)

```swift
UserDefaultKeys.appDisplayOptions         // "com.tpak.meridian.appDisplayOptions" — AppPresentation raw Int
UserDefaultKeys.betaUpdatesEnabled        // "com.tpak.meridian.betaUpdatesEnabled" — Bool
UserDefaultKeys.reopenAppearanceOnLaunch  // "com.tpak.meridian.reopenAppearanceOnLaunch" — Bool (one-shot)
UserDefaultKeys.tahoeOnboardingShown      // "com.tpak.meridian.tahoeOnboardingShown" — Bool (one-shot)
// GlobalShortcutMonitor:
"globalPing"                              // Data (JSON-encoded KeyCombo) — current format
"values.globalPing"                       // [String: Any] — legacy (auto-migrated on first read)
// Sparkle auto-update one-time flags (raw strings, no constant):
"HasSetAutoUpdateDefault"
"HasFixedAutoUpdateSync"
```
