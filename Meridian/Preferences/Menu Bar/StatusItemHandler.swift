// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import Combine
import CoreLoggerKit
import CoreModelKit

internal enum MenubarState {
    case compactText
    case icon
}

/// Shared menu-bar width geometry, referenced by both `bufferCalculatedWidth()` here and
/// `compactWidth(for:with:)` in StatusContainerView so the two stay in sync.
enum MenubarLayoutConstants {
    static let baseWidth = 55
    static let dayBuffer = 12
    static let twelveHourBuffer = 20
    static let secondsBuffer = 15
    static let dateBuffer = 20
    static let colorDotPadding: CGFloat = 14
    // Extra room added to the font-measured two-line width when seconds are
    // shown, so the trailing ":58" isn't clipped. Distinct from secondsBuffer
    // above, which pads the pre-calculated width budget.
    static let measuredSecondsBuffer: CGFloat = 7
}

private enum MenubarTimerConstants {
    static let debounceMilliseconds: Int = 250
    static let toleranceWithSeconds: TimeInterval = 0.5
    static let toleranceWithoutSeconds: TimeInterval = 20
}

// Pure threshold logic for "is Tahoe Control Center silently blocking us?"
// Extracted as a non-private enum so MeridianUnitTests can exercise it
// without spinning up a real NSStatusItem. See issue #125.
internal enum MenubarBlockDetection {
    // Minimum button-window width below which we conclude the status item
    // has been classified as `.ephemeral`. Icon-only mode is narrower (~22pt
    // on average) than compact text mode (≥ ~60pt); the thresholds sit just
    // under each mode's expected rendered width. A blocked item's window is
    // either nil or reports a width of zero, so any non-trivial floor catches
    // it.
    static let iconModeMinimumWidth: CGFloat = 20
    static let compactModeMinimumWidth: CGFloat = 40

    static func isStatusItemBlocked(buttonWindowWidth: CGFloat?, isCompactMode: Bool) -> Bool {
        guard let width = buttonWindowWidth else { return true }
        let threshold = isCompactMode ? compactModeMinimumWidth : iconModeMinimumWidth
        return width < threshold
    }
}

// URL that deep-links to System Settings → Control Center → Menu Bar Only.
// Used by both the StatusItemHandler recovery alert and the About-tab help
// link.
internal enum ControlCenterSettings {
    static let urlString = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
    static let url = URL(string: urlString)!

    static func open() {
        NSWorkspace.shared.open(url)
    }
}

class StatusItemHandler: NSObject {
    // "Midnight Sundial" monochrome template glyph (Assets → MenuBarIcon), shown when the user has
    // no starred cities. isTemplate lets macOS tint it to the bar (white on dark, black on light).
    private lazy var meridianMenubarIcon: NSImage? = {
        let image = NSImage(named: .menubarIcon)
        image?.isTemplate = true
        return image
    }()

    var menubarTimer: Timer?

    var statusItem: NSStatusItem = {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "Meridian"
        (statusItem.button?.cell as? NSButtonCell)?.highlightsBy = NSCell.StyleMask(rawValue: 0)
        return statusItem
    }()

    private var statusContainerView: StatusContainerView?

    private var calendar = Calendar.autoupdatingCurrent

    private var cancellables = Set<AnyCancellable>()

    private let store: DataStore

    // Tahoe (#125): the recovery alert is shown at most once per process so
    // we don't pop a dialog on every UserDefaults-change-triggered
    // setupStatusItem() invocation. The onboarding flag in UserDefaults is a
    // separate, persistent across-launches signal — this is in-memory only.
    private var hasShownBlockedAlertThisSession: Bool = false

    // Brief delay after setupStatusItem() before checking visibility. Control
    // Center takes a beat to position (or reject) a freshly-registered
    // status item; querying too early reports a zero-width window even on
    // healthy installs.
    private let visibilityVerificationDelay: TimeInterval = 1.5

    // Current State might be set twice when the user first launches an app.
    // First, when StatusItemHandler() is instantiated in AppDelegate
    // Second, when AppDelegate.fetchLocalTimezone() is called triggering a customLabel didSet.
    // The debounced UserDefaults observer coalesces these into a single update.
    private var currentState: MenubarState = .icon {
        didSet {
            // Do some cleanup
            switch oldValue {
            case .compactText:
                statusItem.button?.subviews = []
                statusContainerView = nil
                // constructCompactView pins `statusItem.length` to the
                // container width so AppKit reserves the full slot for the
                // compact subviews. The pinned length sticks across state
                // changes, so leaving compact for icon mode without resetting
                // it makes the icon-only slot stay as wide as the previous
                // compact container — visually a too-wide gap around the
                // icon. Hand the slot back to AppKit so it auto-sizes from
                // image again.
                statusItem.length = NSStatusItem.variableLength
            case .icon:
                statusItem.button?.image = nil
            }

            // Now setup for the new menubar state
            switch currentState {
            case .compactText:
                setupForCompactTextMode()
            case .icon:
                setMenubarIcon()
            }

            Logger.debug("Status Bar Current State changed: \(currentState)")
        }
    }

    init(with dataStore: DataStore) {
        store = dataStore
        super.init()

        setupStatusItem()
        setupNotificationObservers()
    }

    func setupStatusItem() {
        // Let's figure out the initial menubar state
        let menubarState: MenubarState = store.menubarTimezones().isEmpty ? .icon : .compactText

        if currentState != menubarState {
            currentState = menubarState
        } else if menubarState == .compactText {
            // Same state, but the favorite list may have changed (toggle
            // on/off without a mode change). The compact container's
            // subviews are decided at construction time, so refresh() —
            // which only re-renders time text on existing subviews — would
            // miss the add/remove. Rebuild the container to pick up the
            // new menubar timezone list.
            setupForCompactTextMode()
        } else {
            // Same state, icon mode. The first call from init() lands here
            // because `currentState` defaults to `.icon` and so does the
            // computed initial state — without an explicit setMenubarIcon
            // the slot is created but never gets its image, so the user
            // sees an invisible (but clickable) status item until something
            // else triggers a state change.
            setMenubarIcon()
        }

        func setSelector() {
            statusItem.button?.action = #selector(menubarIconClicked(_:))
        }

        statusItem.button?.target = self
        statusItem.autosaveName = NSStatusItem.AutosaveName("MeridianStatusItem")
        setSelector()

        scheduleVisibilityVerification()
    }

    // MARK: - Tahoe Visibility Verification (#125)

    /// Schedules an asynchronous check to detect whether macOS Tahoe's
    /// Control Center has silently classified this status item as
    /// `.ephemeral`. Called from setupStatusItem() (initial launch, wake,
    /// and UserDefaults-driven refresh paths) and from AppDelegate's
    /// didBecomeActive listener after the user returns from Settings.
    func scheduleVisibilityVerification() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.verifyStatusItemVisible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + visibilityVerificationDelay,
                                       execute: workItem)
    }

    private func verifyStatusItemVisible() {
        // Tests instantiate AppDelegate which builds a StatusItemHandler;
        // popping a modal NSAlert would hang the test runner. Skip the
        // dialog branch entirely when running under XCTest.
        guard NSClassFromString("XCTestCase") == nil else { return }

        // Once-per-session — the underlying defaults-change observer can
        // re-enter setupStatusItem() many times during normal use.
        guard !hasShownBlockedAlertThisSession else { return }

        let width = statusItem.button?.window?.frame.size.width
        let isCompactMode = currentState == .compactText
        guard MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: width,
                                                       isCompactMode: isCompactMode) else {
            return
        }

        Logger.production("Status item appears blocked by Control Center (width=\(width ?? -1), compact=\(isCompactMode)) — surfacing recovery dialog")
        hasShownBlockedAlertThisSession = true
        showBlockedRecoveryDialog()
    }

    private func showBlockedRecoveryDialog() {
        let body = "macOS appears to be blocking Meridian's menu bar icon. "
            + "Open System Settings → Control Center, scroll to the third-party apps section, and turn on Meridian."
        let alert = NSAlert()
        alert.messageText = "Meridian isn't visible in your menu bar".localized()
        alert.informativeText = body.localized()
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Control Center Settings".localized())
        alert.addButton(withTitle: "Quit Meridian".localized())

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            ControlCenterSettings.open()
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func setupNotificationObservers() {
        DistributedNotificationCenter.default.publisher(for: .interfaceStyleDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.respondToInterfaceStyleChange() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(MenubarTimerConstants.debounceMilliseconds), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.setupStatusItem() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Logger.production("System entering sleep")
                self?.menubarTimer?.invalidate()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Logger.production("System woke from sleep")
                self?.setupStatusItem()
            }
            .store(in: &cancellables)
    }

    private func constructCompactView() {
        statusItem.button?.subviews = []
        statusContainerView = nil

        let menubarTimezones = store.menubarTimezoneObjects()
        if menubarTimezones.isEmpty {
            currentState = .icon
            return
        }

        statusContainerView = StatusContainerView(with: menubarTimezones,
                                                  store: store,
                                                  bufferContainerWidth: bufferCalculatedWidth())
        statusContainerView?.wantsLayer = true
        if let containerView = statusContainerView {
            statusItem.button?.addSubview(containerView)
            statusItem.button?.frame = containerView.bounds
            // NSStatusItem with `.variableLength` auto-sizes from its button's
            // title/image, *not* from added subviews. Without an explicit
            // length the system holds the visible status-bar slot at its
            // single-item default and clips any subview past that width — so
            // a second favourite timezone is rendered into the container but
            // never shown. Pin the slot width to the container so every
            // subview survives. Inherited bug from upstream Clocker; the
            // symptom only surfaces on recent macOS versions that tightened
            // status-bar slot sizing.
            statusItem.length = containerView.bounds.size.width
        }

        // For OS < 11, we need to fix the sizing (width) on the button's window
        // Otherwise, we won't be able to see the menu bar option at all.
        if let window = statusItem.button?.window {
            let currentFrame = window.frame
            let newFrame = NSRect(x: currentFrame.origin.x,
                                  y: currentFrame.origin.y,
                                  width: statusItem.button?.bounds.size.width ?? 0,
                                  height: currentFrame.size.height)
            window.setFrame(newFrame, display: true)
        }
        statusItem.button?.subviews.first?.window?.backgroundColor = NSColor.clear
    }

    // This is called when the Apple interface style pre-Mojave is changed.
    // In High Sierra and before, we could have a dark or light menubar and dock
    // Our icon is template, so it changes automatically; only need to repaint
    // the compact container.
    @objc func respondToInterfaceStyleChange() {
        updateCompactMenubar()
    }

    @objc func menubarIconClicked(_ sender: NSStatusBarButton) {
        guard let mainDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return
        }

        mainDelegate.togglePanel(sender)
    }

    @objc func updateMenubar() {
        guard let fireDate = calculateFireDate() else { return }

        let shouldDisplaySeconds = shouldDisplaySecondsInMenubar()

        menubarTimer?.invalidate()
        menubarTimer = nil

        menubarTimer = Timer(fire: fireDate,
                             interval: 0,
                             repeats: false,
                             block: { [weak self] _ in

            if let strongSelf = self {
                strongSelf.refresh()
            }
        })

        // Tolerance, even a small amount, has a positive imapct on the power usage. As a rule, we set it to 10% of the interval
        menubarTimer?.tolerance = shouldDisplaySeconds ? MenubarTimerConstants.toleranceWithSeconds : MenubarTimerConstants.toleranceWithoutSeconds

        guard let runLoopTimer = menubarTimer else {
            Logger.debug("Timer is unexpectedly nil")
            return
        }

        RunLoop.main.add(runLoopTimer, forMode: .common)
    }

    private func shouldDisplaySecondsInMenubar() -> Bool {
        // Menu-bar seconds are governed by the menu-bar format (Settings ›
        // Menu Bar › Seconds), not the popover's Appearance format —
        // per-city overrideFormat still wins inside shouldShowSeconds.
        let syncedTimezones = store.menubarTimezoneObjects()
        return syncedTimezones.contains { $0.shouldShowSeconds(store.menubarTimezoneFormat()) }
    }

    private func calculateFireDate() -> Date? {
        let shouldDisplaySeconds = shouldDisplaySecondsInMenubar()
        let menubarFavourites = store.menubarTimezones()

        // Derive the component set fresh on every calculation. An instance-level
        // set that only ever gains .second keeps carrying the current seconds
        // after the user switches to a no-seconds format, landing the "next
        // minute" fire date at :SS instead of :00 — the menubar time then lags
        // by up to a minute until relaunch.
        var units: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute]
        if shouldDisplaySeconds {
            units.insert(.second)
        }

        var components = calendar.dateComponents(units, from: Date())

        // We want to update every second only when there's a timezone present!
        if shouldDisplaySeconds, let seconds = components.second, !menubarFavourites.isEmpty {
            components.second = seconds + 1
        } else if let minutes = components.minute {
            components.minute = minutes + 1
            // Fire exactly on the minute boundary regardless of whether .second
            // made it into the component set above.
            components.second = 0
        } else {
            Logger.production("Unable to create date components for menubar timer")
            return nil
        }

        guard let fireDate = calendar.date(from: components) else {
            Logger.production("Unable to form Fire Date")
            return nil
        }

        return fireDate
    }

    func updateCompactMenubar() {
        // This will internally call `statusItemViewSetNeedsDisplay` on all subviews ensuring all text in the menubar is up-to-date.
        statusContainerView?.updateTime()
    }

    func refresh() {
        if currentState == .compactText {
            updateCompactMenubar()
            updateMenubar()
        } else {
            setMenubarIcon()
            menubarTimer?.invalidate()
        }
    }

    func invalidateTimer(showIcon show: Bool, isSyncing sync: Bool) {
        let menubarFavourites = store.menubarTimezones()

        if menubarFavourites.isEmpty {
            Logger.debug("Invalidating menubar timer")

            invalidation()

            if show {
                currentState = .icon
            }

        } else if sync {
            Logger.debug("Invalidating menubar timer for sync")

            invalidation()

            if show {
                setMenubarIcon()
            }

        } else {
            Logger.debug("Not stopping menubar timer")
        }
    }

    private func invalidation() {
        menubarTimer?.invalidate()
    }

    private func setMenubarIcon() {
        if statusItem.button?.subviews.isEmpty == false {
            statusItem.button?.subviews = []
        }

        statusItem.button?.title = UserDefaultKeys.emptyString
        statusItem.button?.image = meridianMenubarIcon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Meridian"
    }

    private func setupForCompactTextMode() {
        // Let's invalidate the previous timer
        menubarTimer?.invalidate()
        menubarTimer = nil

        constructCompactView()
        updateMenubar()
    }

    private func bufferCalculatedWidth() -> Int {
        var totalWidth = MenubarLayoutConstants.baseWidth

        if store.shouldShowDayInMenubar() {
            totalWidth += MenubarLayoutConstants.dayBuffer
        }

        if store.isBufferRequiredForTwelveHourFormats() {
            totalWidth += MenubarLayoutConstants.twelveHourBuffer
        }

        if store.shouldShowDateInMenubar() {
            totalWidth += MenubarLayoutConstants.dateBuffer
        }

        return totalWidth
    }
}
