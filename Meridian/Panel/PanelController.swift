// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

private enum PanelLayout {
    static let dragHandleTopAnchor: CGFloat = 6
    static let dragHandleHeight: CGFloat = 16
    static let pinButtonTrailingMargin: CGFloat = 8
    static let pinButtonSize: CGFloat = 22
    static let versionLabelTrailingMargin: CGFloat = 34 // 22pt button + 4pt gap + 8pt margin
    static let frameYPointOffset: CGFloat = 2
    static let minimumSpaceBetweenWindowAndScreenEdge: CGFloat = 10
}

private enum PanelAnimation {
    static let minimizeDuration: TimeInterval = 0.1
}

class PanelController: ParentPanelController {
    @objc dynamic var hasActivePanel: Bool = false
    private var isShowingContextMenu = false
    private var pinButton: NSButton?
    private var dragHandleView: PanelDragHandleView?

    @IBOutlet var backgroundView: BackgroundPanelView!

    override func awakeFromNib() {
        super.awakeFromNib()

        enablePerformanceLoggingIfNeccessary()

        window?.title = "Meridian Panel"
        window?.setAccessibilityIdentifier("Meridian Panel")
        // Otherwise, the panel can be dragged around while we try to scroll through the modern slider
        window?.isMovableByWindowBackground = false

        if let panel = window {
            panel.acceptsMouseMovedEvents = true
            panel.isOpaque = false
            panel.backgroundColor = NSColor.clear
        }

        applyWindowMode()

        mainTableView.registerForDraggedTypes([.dragSession])

        super.updatePanelColor()

        super.updateDefaultPreferences()

        setupFloatingModeObserver()
        setupFloatModeUI()
    }

    private func enablePerformanceLoggingIfNeccessary() {
        if !ProcessInfo.processInfo.environment.keys.contains("ENABLE_PERF_LOGGING") {
            PerfLogger.disable()
        }
    }

    private var isFloatingMode: Bool {
        return dataStore.shouldDisplay(.showAppInForeground)
    }

    private func applyWindowMode() {
        guard let panel = window else { return }
        if isFloatingMode {
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            // Restore saved position, or center on screen if first time
            let restored = panel.setFrameUsingName("MeridianFloatingPanel")
            panel.setFrameAutosaveName("MeridianFloatingPanel")
            if !restored {
                panel.center()
            }
        } else {
            panel.isMovableByWindowBackground = false
            panel.level = .popUpMenu
            panel.collectionBehavior = []
            panel.hidesOnDeactivate = false
            panel.setFrameAutosaveName("")
        }
        updateFloatModeUI()
    }

    private func setupFloatModeUI() {
        guard let contentView = window?.contentView,
              let footer = settingsButton?.superview else { return }

        // Drag handle: thin strip at top of panel for repositioning in float mode.
        let drag = PanelDragHandleView()
        drag.translatesAutoresizingMaskIntoConstraints = false
        drag.isHidden = true
        drag.toolTip = "Drag to move the panel"
        contentView.addSubview(drag)
        NSLayoutConstraint.activate([
            drag.topAnchor.constraint(equalTo: contentView.topAnchor, constant: PanelLayout.dragHandleTopAnchor),
            drag.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            drag.heightAnchor.constraint(equalToConstant: PanelLayout.dragHandleHeight),
        ])
        dragHandleView = drag

        // Pin button: quick float toggle next to the version label in the footer.
        let pin = NSButton()
        pin.translatesAutoresizingMaskIntoConstraints = false
        pin.bezelStyle = .recessed
        pin.isBordered = false
        pin.imagePosition = .imageOnly
        pin.target = self
        pin.action = #selector(toggleFloatingMode)
        footer.addSubview(pin)
        NSLayoutConstraint.activate([
            pin.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            pin.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -PanelLayout.pinButtonTrailingMargin),
            pin.widthAnchor.constraint(equalToConstant: PanelLayout.pinButtonSize),
            pin.heightAnchor.constraint(equalToConstant: PanelLayout.pinButtonSize),
        ])
        // Shrink version label trailing margin to make room for the pin button.
        for c in footer.constraints where c.secondItem === versionStatusLabel && c.secondAttribute == .trailing {
            c.constant = PanelLayout.versionLabelTrailingMargin
            break
        }
        pinButton = pin
        updateFloatModeUI()
    }

    private func updateFloatModeUI() {
        let floating = isFloatingMode
        dragHandleView?.isHidden = !floating
        let symbol = floating ? "pin.fill" : "pin"
        pinButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: floating ? "Unpin from Desktop" : "Pin to Desktop")
        pinButton?.contentTintColor = floating ? .controlAccentColor : .secondaryLabelColor
        pinButton?.toolTip = floating ? "Unpin from Desktop" : "Pin to Desktop"
    }

    private func setupFloatingModeObserver() {
        UserDefaults.standard.publisher(for: \.displayAppAsForegroundApp)
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyWindowMode()  // also calls updateFloatModeUI
                if self?.isFloatingMode == true, self?.window?.isVisible == false {
                    self?.setActivePanel(newValue: true)
                }
            }
            .store(in: &cancellables)
    }

    func setFrameTheNewWay(_ rect: NSRect, _ maxX: CGFloat) {
        // Calculate window's top left point.
        // First, center window under status item.
        let width = (window?.frame)!.width
        var xPoint = CGFloat(roundf(Float(rect.midX - width / 2)))
        let yPoint = CGFloat(rect.minY - PanelLayout.frameYPointOffset)

        if xPoint + width + PanelLayout.minimumSpaceBetweenWindowAndScreenEdge > maxX {
            xPoint = maxX - width - PanelLayout.minimumSpaceBetweenWindowAndScreenEdge
        }

        window?.setFrameTopLeftPoint(NSPoint(x: xPoint, y: yPoint))
        window?.invalidateShadow()
    }

    func open() {
        PerfLogger.startMarker("Open")

        guard isWindowLoaded == true else {
            return
        }

        // Cancel any in-flight fade-out animation and restore full opacity immediately.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window?.animator().alphaValue = 1
        }

        // Keep button state in sync regardless of how the panel was opened (click vs programmatic).
        if let btn = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel().statusItem.button {
            btn.state = .on
        }

        super.dismissRowActions()

        updateDefaultPreferences()

        if dataStore.timezones().isEmpty || dataStore.shouldDisplay(.futureSlider) == false {
            modernContainerView.isHidden = true
        } else if let value = dataStore.retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber, modernContainerView != nil {
            if value.intValue == 1 {
                modernContainerView.isHidden = true
            } else if value.intValue == 0 {
                modernContainerView.isHidden = false
            }
        }

        // Reset future slider value to zero
        closestQuarterTimeRepresentation = timeScrollerViewModel.findClosestQuarterTimeApproximation()
        modernSliderLabel.stringValue = "Time Scroller"
        resetModernSliderButton.isHidden = true

        if modernSlider != nil {
            let indexPaths: Set<IndexPath> = Set([IndexPath(item: modernSlider.numberOfItems(inSection: 0) / 2, section: 0)])
            modernSlider.scrollToItems(at: indexPaths, scrollPosition: .centeredHorizontally)
        }

        goForwardButton.alphaValue = 0
        goBackwardsButton.alphaValue = 0

        setTimezoneDatasourceSlider(sliderValue: 0)

        if !isFloatingMode {
            setPanelFrame()
        }

        startWindowTimer()

        super.setScrollViewConstraint()

        // This is done to make the UI look updated.
        mainTableView.reloadData()

        log()

        PerfLogger.endMarker("Open")
    }

    // New way to set the panel's frame.
    // This takes into account the screen's dimensions.
    private func setPanelFrame() {
        PerfLogger.startMarker("Set Panel Frame")

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return
        }

        let statusItem = appDelegate.statusItemForPanel().statusItem
        guard let statusWindow = statusItem.button?.window,
              let statusButton = statusItem.button else {
            return
        }

        var statusItemFrame = statusWindow.convertToScreen(statusButton.frame)
        var testPoint = statusItemFrame.origin
        testPoint.y -= 100

        let statusItemScreen = NSScreen.screens.first(where: { $0.frame.contains(testPoint) }) ?? NSScreen.main
        guard let resolvedScreen = statusItemScreen else { return }

        let screenMaxX = resolvedScreen.frame.maxX
        let minY = min(statusItemFrame.origin.y, resolvedScreen.frame.maxY)
        statusItemFrame.origin.y = minY

        setFrameTheNewWay(statusItemFrame, screenMaxX)
        PerfLogger.endMarker("Set Panel Frame")
    }

    /// Groups all panel-open display preferences for structured logging, replacing 8 separate NSNumber guard bindings.
    private struct LogDisplayPreferences {
        let theme: NSNumber
        let displayFutureSlider: NSNumber
        let showAppInForeground: NSNumber
        let relativeDateKey: NSNumber
        let fontSize: NSNumber
        let sunriseTime: NSNumber
        let showDayInMenu: NSNumber
        let showDateInMenu: NSNumber
        let showPlaceInMenu: NSNumber

        init?(from store: DataStoring) {
            guard let theme = store.retrieve(key: UserDefaultKeys.themeKey) as? NSNumber,
                  let displayFutureSlider = store.retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber,
                  let showAppInForeground = store.retrieve(key: UserDefaultKeys.showAppInForeground) as? NSNumber,
                  let relativeDateKey = store.retrieve(key: UserDefaultKeys.relativeDateKey) as? NSNumber,
                  let fontSize = store.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber,
                  let sunriseTime = store.retrieve(key: UserDefaultKeys.sunriseSunsetTime) as? NSNumber,
                  let showDayInMenu = store.retrieve(key: UserDefaultKeys.showDayInMenu) as? NSNumber,
                  let showDateInMenu = store.retrieve(key: UserDefaultKeys.showDateInMenu) as? NSNumber,
                  let showPlaceInMenu = store.retrieve(key: UserDefaultKeys.showPlaceInMenu) as? NSNumber
            else { return nil }
            self.theme = theme
            self.displayFutureSlider = displayFutureSlider
            self.showAppInForeground = showAppInForeground
            self.relativeDateKey = relativeDateKey
            self.fontSize = fontSize
            self.sunriseTime = sunriseTime
            self.showDayInMenu = showDayInMenu
            self.showDateInMenu = showDateInMenu
            self.showPlaceInMenu = showPlaceInMenu
        }
    }

    private func log() {
        PerfLogger.startMarker("Logging")

        let preferences = dataStore.timezones()

        guard let prefs = LogDisplayPreferences(from: dataStore),
              let country = Locale.autoupdatingCurrent.region?.identifier
        else {
            return
        }

        var relativeDate = "Relative"
        if prefs.relativeDateKey.isEqual(to: NSNumber(value: 1)) {
            relativeDate = "Actual Day"
        } else if prefs.relativeDateKey.isEqual(to: NSNumber(value: 2)) {
            relativeDate = "Date"
        }

        let panelEvent: [String: Any] = [
            "Theme": prefs.theme.isEqual(to: NSNumber(value: 0)) ? "Default" : "Black",
            "Display Future Slider": prefs.displayFutureSlider.isEqual(to: NSNumber(value: 0)) ? "Yes" : "No",
            "Meridian mode": prefs.showAppInForeground.isEqual(to: NSNumber(value: 0)) ? "Menubar" : "Floating",
            "Relative Date": relativeDate,
            "Font Size": prefs.fontSize,
            "Sunrise Sunset": prefs.sunriseTime.isEqual(to: NSNumber(value: 0)) ? "Yes" : "No",
            "Show Day in Menu": prefs.showDayInMenu.isEqual(to: NSNumber(value: 0)) ? "Yes" : "No",
            "Show Date in Menu": prefs.showDateInMenu.isEqual(to: NSNumber(value: 0)) ? "Yes" : "No",
            "Show Place in Menu": prefs.showPlaceInMenu.isEqual(to: NSNumber(value: 0)) ? "Yes" : "No",
            "Country": country,
            "Number of Timezones": preferences.count
        ]

        Logger.debug("openedPanel: \(panelEvent)")

        PerfLogger.endMarker("Logging")
    }

    private func startWindowTimer() {
        PerfLogger.startMarker("Start Window Timer")

        stopMenubarTimerIfNeccesary()

        if let timer = parentTimer, timer.state == .paused {
            parentTimer?.start()

            PerfLogger.endMarker("Start Window Timer")

            return
        }

        startTimer()

        PerfLogger.endMarker("Start Window Timer")
    }

    private func startTimer() {
        Logger.debug("Start timer called")

        parentTimer = Repeater(interval: .seconds(1), mode: .infinite) { _ in
            OperationQueue.main.addOperation {
                self.updateTime()
            }
        }
        parentTimer?.start()
    }

    private func stopMenubarTimerIfNeccesary() {
        let count = dataStore.menubarTimezones().count

        if count >= 1 {
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                Logger.debug("We will be invalidating the menubar timer as we want the parent timer to take care of both panel and menubar ")

                delegate.invalidateMenubarTimer(false)
            }
        }
    }

    func cancelOperation() {
        setActivePanel(newValue: false)
    }

    func hasActivePanelGetter() -> Bool {
        return hasActivePanel
    }

    func minimize() {
        let delegate = NSApplication.shared.delegate as? AppDelegate
        let count = DataStore.shared().menubarTimezones().count
        if count >= 1 {
            if let handler = delegate?.statusItemForPanel(), let timer = handler.menubarTimer, !timer.isValid {
                delegate?.setupMenubarTimer()
            }
        }

        parentTimer?.pause()

        updatePopoverDisplayState()
        additionalOptionsPopover?.close()

        // Keep button state in sync regardless of how the panel was closed (click vs programmatic).
        if let btn = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel().statusItem.button {
            btn.state = .off
        }

        let windowToHide = window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = PanelAnimation.minimizeDuration
            windowToHide?.animator().alphaValue = 0
        }, completionHandler: {
            windowToHide?.orderOut(nil)
        })

        datasource = nil
        parentTimer?.pause()
        parentTimer = nil
    }

    func setActivePanel(newValue: Bool) {
        hasActivePanel = newValue
        if hasActivePanel {
            open()
        } else {
            minimize()
        }
    }

    class func panel() -> PanelController? {
        let panel = NSApplication.shared.windows.compactMap { window -> PanelController? in

            guard let parent = window.windowController as? PanelController else {
                return nil
            }

            return parent
        }

        return panel.first
    }

    override func showNotesPopover(forRow row: Int, relativeTo positioningRect: NSRect, andButton target: NSButton!) -> Bool {
        guard let target = target else { return false }

        // The NotesPopover XIB/controller was removed in the strip commit.
        // Update the button icon for the ellipsis toggle but don't try to show a popover.
        if let popover = additionalOptionsPopover, popover.isShown, row == previousPopoverRow {
            popover.close()
            target.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Options")
            previousPopoverRow = -1
            return false
        }

        target.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Options")
        previousPopoverRow = row

        if let timer = parentTimer, timer.state == .paused {
            timer.start()
        }

        return true
    }

    func setupMenubarTimer() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setupMenubarTimer()
        }
    }

    func pauseTimer() {
        if let timer = parentTimer {
            timer.pause()
        }
    }

    func refreshBackgroundView() {
        backgroundView.setNeedsDisplay(backgroundView.bounds)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == NSEvent.Phase.ended {
            Logger.debug("Scroll Event Ended")
        }

        // We only want to move the slider if the slider is visible.
        // If the parent view is hidden, then that doesn't automatically mean that all the childViews are also hidden
        // Hence, check if the parent view is totally hidden or not..
    }

    @objc func toggleFloatingMode() {
        let newValue = isFloatingMode ? 0 : 1
        UserDefaults.standard.set(newValue, forKey: UserDefaultKeys.showAppInForeground)
        applyWindowMode()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contentView = window?.contentView else { return }
        isShowingContextMenu = true
        let menu = NSMenu(title: "Panel Options")
        let title = isFloatingMode ? "Unpin from Desktop" : "Pin to Desktop"
        let item = NSMenuItem(title: title, action: #selector(toggleFloatingMode), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        isShowingContextMenu = false
    }
}

extension PanelController: NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        if isFloatingMode {
            setActivePanel(newValue: false)
            return false
        }
        return true
    }

    func windowWillClose(_: Notification) {
        parentTimer = nil
        setActivePanel(newValue: false)
    }

    func windowDidResignKey(_: Notification) {
        if isFloatingMode || isShowingContextMenu {
            return
        }
        parentTimer = nil

        if let isVisible = window?.isVisible, isVisible == true {
            setActivePanel(newValue: false)
        }
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.statusItemForPanel().statusItem.button?.state = .off
        }
    }
}
