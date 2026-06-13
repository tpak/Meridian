// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLoggerKit
import CoreModelKit

private enum TimeFormatMenuSeparatorIndices {
    static let withSecondsIndex: Int = 2
    static let twelveHourWithPrecedingZeroIndex: Int = 5
    static let twelveHourWithoutAMPMIndex: Int = 8
}

private enum PreviewTableViewLayout {
    static let defaultRowHeight: Int = 60
    static let largerFontRowHeight: Int = 65
}

private enum AppearanceTabIndex {
    static let initial: Int = 0
}

class AppearanceViewController: ParentViewController {
    @IBOutlet var timeFormat: NSPopUpButton!
    @IBOutlet var theme: NSPopUpButton!
    @IBOutlet var teamAccentPopup: NSPopUpButton!
    @IBOutlet var accentColorInfoButton: NSButton!
    @IBOutlet var informationLabel: NSTextField!
    @IBOutlet var sliderDayRangePopup: NSPopUpButton!
    @IBOutlet var visualEffectView: NSVisualEffectView!
    @IBOutlet var includeDayInMenubarControl: NSSegmentedControl!
    @IBOutlet var includeDateInMenubarControl: NSSegmentedControl!
    @IBOutlet var includePlaceNameControl: NSSegmentedControl!
    @IBOutlet var appearanceTab: NSTabView!
    @IBOutlet var appDisplayControl: NSSegmentedControl!
    @IBOutlet var floatOnTopControl: NSSegmentedControl!
    @IBOutlet var floatOnTopLabel: NSTextField!
    // Issue #97 — explicit outlets so viewWillAppear can set initial segments
    // for controls that previously used Cocoa bindings to legacy keys.
    @IBOutlet var sunriseControl: NSSegmentedControl!
    @IBOutlet var futureSliderControl: NSSegmentedControl!

    private static let sliderDayValues = [1, 2, 3, 4, 5, 6, 7, 14, 30, 90]

    private var previewTimezones: [TimezoneData] = []

    /// Lazy popover for the trademark / fan-attribution disclaimer shown when
    /// the user clicks the (i) button next to the team accent picker.
    private lazy var accentInfoPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = AccentColorInfoViewController()
        return popover
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        informationLabel.stringValue = "Favourite a timezone to enable menubar display options.".localized()
        informationLabel.textColor = NSColor.secondaryLabelColor
        informationLabel.setAccessibilityIdentifier("InformationLabel")

        setupTimeFormatPopup()
        setupTeamAccentPopup()

        sliderDayRangePopup.removeAllItems()
        sliderDayRangePopup.addItems(withTitles: Self.sliderDayValues.map { days in
            switch days {
            case 1: return "1 day"
            case 30: return "1 month"
            case 90: return "3 months"
            default: return "\(days) days"
            }
        })

        setup()

        previewTimezones = [TimezoneData(with: ["customLabel": "San Francisco",
                                                "formattedAddress": "San Francisco",
                                                "place_id": "TestIdentifier",
                                                "timezoneID": "America/Los_Angeles",
                                                "nextUpdate": "",
                                                "latitude": "37.7749295",
                                                "longitude": "-122.4194155"])]

        appearanceTab.selectTabViewItem(at: AppearanceTabIndex.initial)

        previewPanelTableView.dataSource = self
        previewPanelTableView.delegate = self
        previewPanelTableView.reloadData()
        previewPanelTableView.selectionHighlightStyle = .none
        previewPanelTableView.enclosingScrollView?.hasVerticalScroller = false
        previewPanelTableView.enclosingScrollView?.wantsLayer = true
        previewPanelTableView.enclosingScrollView?.layer?.cornerRadius = 12
    }

    /// Builds the F1 team accent popup from `TeamAccent.allCases`. The enum
    /// is the single source of truth for the team list — storyboard menu
    /// items are placeholders and get replaced here on every load.
    private func setupTeamAccentPopup() {
        guard let popup = teamAccentPopup else { return }
        popup.removeAllItems()
        popup.addItems(withTitles: TeamAccent.allCases.map { $0.displayName })
        let current = DataStore.shared().teamAccent
        if let index = TeamAccent.allCases.firstIndex(of: current) {
            popup.selectItem(at: index)
        }
        // Wire target/action programmatically as a safety net. The storyboard
        // also wires this via @IBAction, but if storyboard parsing skips the
        // connection (or the outlet/action is renamed without a sweep) the
        // popup still functions.
        popup.target = self
        popup.action = #selector(teamAccentChanged(_:))
        popup.setAccessibilityIdentifier("TeamAccentPopover")

        if let info = accentColorInfoButton {
            info.image = NSImage(systemSymbolName: "info.circle",
                                 accessibilityDescription: "About accent colors".localized())
            info.contentTintColor = NSColor.secondaryLabelColor
            info.toolTip = "About these colors".localized()
            info.setAccessibilityLabel("About accent colors".localized())
            info.target = self
            info.action = #selector(showAccentColorInfo(_:))
        }
    }

    private func setupTimeFormatPopup() {
        let supportedTimeFormats = ["h:mm a (7:08 PM)",
                                    "HH:mm (19:08)",
                                    "-- With Seconds --",
                                    "h:mm:ss a (7:08:09 PM)",
                                    "HH:mm:ss (19:08:09)",
                                    "-- 12 Hour with Preceding 0 --",
                                    "hh:mm a (07:08 PM)",
                                    "hh:mm:ss a (07:08:09 PM)",
                                    "-- 12 Hour w/o AM/PM --",
                                    "hh:mm (07:08)",
                                    "hh:mm:ss (07:08:09)",
                                    "Epoch Time"]
        timeFormat.removeAllItems()
        timeFormat.addItems(withTitles: supportedTimeFormats)
        timeFormat.item(at: TimeFormatMenuSeparatorIndices.withSecondsIndex)?.isEnabled = false
        timeFormat.item(at: TimeFormatMenuSeparatorIndices.twelveHourWithPrecedingZeroIndex)?.isEnabled = false
        timeFormat.item(at: TimeFormatMenuSeparatorIndices.twelveHourWithoutAMPMIndex)?.isEnabled = false
        timeFormat.autoenablesItems = false
        timeFormat.selectItem(at: dataStore.timezoneFormat().intValue)
        timeFormat.setAccessibilityIdentifier("TimeFormatPopover")
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        let menubarFavourites = dataStore.menubarTimezones()
        visualEffectView.isHidden = menubarFavourites.isEmpty ? false : true
        informationLabel.isHidden = menubarFavourites.isEmpty ? false : true

        if let storedValue = dataStore.retrieve(key: UserDefaultKeys.futureSliderRange) as? NSNumber {
            let dayValue = storedValue.intValue
            if let index = Self.sliderDayValues.firstIndex(of: dayValue) {
                sliderDayRangePopup.selectItem(at: index)
            } else {
                // Legacy: stored value was an index (0-6), migrate to day value
                let legacyDays = dayValue + 1
                if let index = Self.sliderDayValues.firstIndex(of: legacyDays) {
                    sliderDayRangePopup.selectItem(at: index)
                    UserDefaults.standard.set(legacyDays, forKey: UserDefaultKeys.futureSliderRange)
                }
            }
        }

        // Issue #97 — segmented controls used to read their initial state via
        // Cocoa bindings to legacy UserDefaults keys; bindings were removed so
        // we set initial state from the typed accessors here. The convention is
        // segment 0 = Yes/show, segment 1 = No/hide, matching the storyboard's
        // segment labels.
        let store = DataStore.shared()
        appDisplayControl.setSelected(true, forSegment: store.appPresentation == .menubarOnly ? 0 : 1)
        floatOnTopControl.setSelected(true, forSegment: store.floatOnTop ? 0 : 1)
        sunriseControl.setSelected(true, forSegment: store.showSunriseSunset ? 0 : 1)
        futureSliderControl.setSelected(true, forSegment: store.showFutureSlider ? 0 : 1)
        includeDayInMenubarControl.setSelected(true, forSegment: store.showDayInMenubar ? 0 : 1)
        includeDateInMenubarControl.setSelected(true, forSegment: store.showDateInMenubar ? 0 : 1)
        includePlaceNameControl.setSelected(true, forSegment: store.showPlaceNameInMenubar ? 0 : 1)

        // Time format popup binding to is24HourFormatSelected was dropped
        // because the migration deletes that key — refresh the popup
        // selection from the typed accessor here so it tracks imports and
        // tab re-entry.
        timeFormat.selectItem(at: store.timezoneFormat().intValue)

        // Team accent: refresh on tab re-entry so settings imports flow in.
        if let popup = teamAccentPopup,
           let index = TeamAccent.allCases.firstIndex(of: store.teamAccent) {
            popup.selectItem(at: index)
        }

        // The preview table renders sample rows using TimezoneDataOperations
        // which reads the live time format. Settings import doesn't notify
        // this view controller, so refresh on tab re-entry.
        previewPanelTableView.reloadData()
    }

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

    // Panel Preview
    @IBOutlet var previewPanelTableView: NSTableView!

    private func setup() {
        timeFormatLabel.stringValue = "Time Format".localized()
        panelTheme.stringValue = "Panel Theme".localized()
        accentColorLabel?.stringValue = "Accent Color".localized()
        dayDisplayOptionsLabel.stringValue = "Day Display Options".localized()
        showSliderLabel.stringValue = "Time Scroller".localized()
        showSunriseLabel.stringValue = "Show Sunrise/Sunset".localized()
        largerTextLabel.stringValue = "Larger Text".localized()
        futureSliderRangeLabel.stringValue = "Future Slider Range".localized()
        includeDateLabel.stringValue = "Include Date".localized()
        includeDayLabel.stringValue = "Include Day".localized()
        includePlaceLabel.stringValue = "Include Place Name".localized()
        previewLabel.stringValue = "Preview".localized()
        miscelleaneousLabel.stringValue = "Miscellaneous".localized()
        floatOnTopLabel.stringValue = "Float on Top".localized()
        appDisplayLabel.stringValue = "Show Meridian in".localized()

        [timeFormatLabel, panelTheme, accentColorLabel,
         dayDisplayOptionsLabel, showSliderLabel,
         showSunriseLabel, largerTextLabel, futureSliderRangeLabel,
         includeDayLabel, includeDateLabel, includePlaceLabel, appDisplayLabel,
         previewLabel, miscelleaneousLabel, floatOnTopLabel].forEach {
            $0?.textColor = NSColor.labelColor
        }

        previewPanelTableView.backgroundColor = NSColor.windowBackgroundColor
    }

    @IBAction func timeFormatSelectionChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        DataStore.shared().timeFormat = TimeFormat(rawValue: index) ?? .twelveHour
        refresh(panel: true)

        if let selectedFormat = sender.selectedItem?.title,
           selectedFormat.contains("ss") {
            Logger.debug("Selected format contains timezone format")
            guard let panelController = PanelController.panel() else { return }
            panelController.pauseTimer()
        }

        updateStatusItem()
        previewPanelTableView.reloadData()
    }

    @IBAction func teamAccentChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < TeamAccent.allCases.count else { return }
        let team = TeamAccent.allCases[index]
        DataStore.shared().teamAccent = team
        Logger.production("[Accent] teamAccentChanged: team=\(team.displayName)")
        // Notify observers — panel pin/slider buttons and Preferences
        // toolbar icons repaint immediately with the new color.
        NSApp.mer_invalidateAccentEverywhere()
        previewPanelTableView.reloadData()

        // The remaining accent surfaces in Settings — popup highlights,
        // segmented control fills, focus rings, checkbox checks, the
        // toolbar tab text labels — are tinted by AppKit through code
        // paths that don't refresh at runtime no matter how the
        // app pokes them (verified across betas 2-7). Offer the user
        // the only mechanism that works: a quit+relaunch.
        promptForRestart(applying: team)
    }

    @IBAction func showAccentColorInfo(_ sender: NSButton) {
        if accentInfoPopover.isShown {
            accentInfoPopover.performClose(sender)
            return
        }
        accentInfoPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func promptForRestart(applying team: TeamAccent) {
        let alert = NSAlert()
        alert.messageText = "Restart Meridian to apply \(team.displayName) throughout?"
        alert.informativeText = """
        macOS doesn't allow accent color changes to apply to existing AppKit \
        controls (popups, segmented controls, toolbar text) at runtime. The \
        panel and toolbar icons have already updated. To apply \(team.displayName) \
        to the rest of the UI, Meridian needs to relaunch.

        Your timezones and other settings are preserved.
        """
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Apply at Next Launch")
        alert.alertStyle = .informational

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Persist a flag so AppDelegate reopens Settings → Appearance
        // after the new instance launches; the user lands back where
        // they were instead of an empty menu bar app.
        UserDefaults.standard.set(true, forKey: UserDefaultKeys.reopenAppearanceOnLaunch)
        UserDefaults.standard.synchronize()

        // Spawn a new instance, then terminate this one. `open -n` makes
        // the new instance start fresh rather than activating the
        // existing one (which is about to terminate anyway).
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        do {
            try task.run()
        } catch {
            Logger.production("[Accent] restart spawn failed: \(error)")
        }

        // Brief delay so the spawn has time to register before we
        // terminate; otherwise macOS may treat it as a duplicate-launch
        // suppression and the new instance never appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.pauseBeforeRelaunchTermination) {
            NSApp.terminate(nil)
        }
    }

    @IBAction func themeChanged(_ sender: NSPopUpButton) {
        let selectedMenuItem = sender.indexOfSelectedItem

        refresh(panel: false)

        guard let panelController = PanelController.panel() else {
            return
        }

        panelController.refreshBackgroundView()

        let defaultTimezones = panelController.defaultPreferences
        if defaultTimezones.isEmpty {
            panelController.updatePanelColor()
        }

        panelController.updateTableContent()

        switch selectedMenuItem {
        case 0:
            Logger.debug("Theme: themeSelected=Light")
        case 1:
            Logger.debug("Theme: themeSelected=Dark")
        case 2:
            Logger.debug("Theme: themeSelected=System")
        default:
            Logger.debug("Theme: themeSelected=System")
        }
    }

    private func loggingStringForRelativeDisplaySelection(_ selection: Int) -> String {
        switch selection {
        case 0:
            return "Relative Day"
        case 1:
            return "Actual Day"
        case 2:
            return "Actual Date Day"
        case 3:
            return "Hide"
        default:
            return "Unexpected Selection"
        }
    }

    @IBAction func changeRelativeDayDisplay(_ sender: NSSegmentedControl) {
        Logger.debug("RelativeDate: dayPreference=\(loggingStringForRelativeDisplaySelection(sender.selectedSegment))")

        refresh(panel: true)

        previewPanelTableView.reloadData()
    }

    @IBAction func showFutureSlider(_ sender: NSSegmentedControl) {
        // Segment 0 = "Show", Segment 1 = "Hide".
        DataStore.shared().showFutureSlider = sender.selectedSegment == 0
        refresh(panel: false)
    }

    @IBAction func showSunriseSunset(_ sender: NSSegmentedControl) {
        let enabled = sender.selectedSegment == 0
        DataStore.shared().showSunriseSunset = enabled
        Logger.debug("Sunrise Sunset: IsItDisplayed=\(enabled ? "YES" : "NO")")
        refresh(panel: true)
        previewPanelTableView.reloadData()
    }

    @IBAction func changeAppDisplayOptions(_ sender: NSSegmentedControl) {
        // Segment 0 = Menubar only, Segment 1 = Menubar + Dock.
        let presentation: AppPresentation = sender.selectedSegment == 0 ? .menubarOnly : .menubarAndDock
        DataStore.shared().appPresentation = presentation
        switch presentation {
        case .menubarOnly:
            Logger.debug("Dock Mode: Selection=Menubar")
            NSApp.setActivationPolicy(.accessory)
        case .menubarAndDock:
            Logger.debug("Dock Mode: Selection=Menubar and Dock")
            NSApp.setActivationPolicy(.regular)
        }
    }

    @IBAction func floatOnTopChanged(_ sender: NSSegmentedControl) {
        // Segment 0 = "Yes" (float on), Segment 1 = "No" (menubar).
        let enabled = sender.selectedSegment == 0
        DataStore.shared().floatOnTop = enabled
        Logger.debug("Float on Top: \(enabled ? "Enabled" : "Disabled")")
    }

    private func refresh(panel: Bool) {
        DispatchQueue.main.async {
            if panel {
                guard let panelController = PanelController.panel() else { return }

                let futureSliderBounds = panelController.modernSlider.bounds
                panelController.modernSlider.setNeedsDisplay(futureSliderBounds)

                panelController.updateDefaultPreferences()
                panelController.updateTableContent()
                panelController.setupMenubarTimer()
            }
        }
    }

    @IBAction func displayDayInMenubarAction(_ sender: NSSegmentedControl) {
        DataStore.shared().showDayInMenubar = sender.selectedSegment == 0
        updateStatusItem()
    }

    @IBAction func displayDateInMenubarAction(_ sender: NSSegmentedControl) {
        DataStore.shared().showDateInMenubar = sender.selectedSegment == 0
        updateStatusItem()
    }

    @IBAction func displayPlaceInMenubarAction(_ sender: NSSegmentedControl) {
        DataStore.shared().showPlaceNameInMenubar = sender.selectedSegment == 0
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let statusItem = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else {
            return
        }
        statusItem.setupStatusItem()
    }

    @IBAction func fontSliderChanged(_: Any) {
        previewPanelTableView.reloadData()
    }

    // MARK: - Slider Day Range

    @IBAction func sliderDayRangeChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < Self.sliderDayValues.count else { return }
        let dayValue = Self.sliderDayValues[index]
        UserDefaults.standard.set(dayValue, forKey: UserDefaultKeys.futureSliderRange)
    }

}

extension AppearanceViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        return 1
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard !previewTimezones.isEmpty else {
            return nil
        }

        let cellID = NSUserInterfaceItemIdentifier(rawValue: "previewTimezoneCell")
        guard let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? TimezoneCellView else {
            Logger.debug("Unable to create tableviewcell")
            return NSView()
        }

        let currentModel = previewTimezones[row]
        let operation = TimezoneDataOperations(with: currentModel, store: dataStore)

        cellView.sunriseSetTime.stringValue = operation.formattedSunriseTime(with: 0)
        cellView.sunriseImage.image = currentModel.isSunriseOrSunset
            ? NSImage(systemSymbolName: "sunrise.fill", accessibilityDescription: "Sunrise")
            : NSImage(systemSymbolName: "sunset.fill", accessibilityDescription: "Sunset")
        cellView.relativeDate.stringValue = operation.date(with: 0, displayType: .panel)
        cellView.rowNumber = row
        cellView.customName.stringValue = currentModel.formattedTimezoneLabel()
        cellView.time.stringValue = operation.time(with: 0)
        cellView.dstLabel.stringValue = UserDefaultKeys.emptyString
        cellView.currentLocationIndicator.isHidden = !currentModel.isSystemTimezone
        cellView.time.setAccessibilityIdentifier("ActualTime")
        cellView.layout(with: currentModel)

        cellView.setAccessibilityIdentifier(currentModel.formattedTimezoneLabel())
        cellView.setAccessibilityLabel(currentModel.formattedTimezoneLabel())

        return cellView
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let userFontSize = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber, previewTimezones.count > row {
            let rowHeight: Int = userFontSize == 4 ? PreviewTableViewLayout.defaultRowHeight : PreviewTableViewLayout.largerFontRowHeight
            return CGFloat(rowHeight + (userFontSize.intValue * 2))
        }

        return 0
    }
}

/// Disclaimer popover shown next to the team accent picker. The text
/// acknowledges that the colors are fan approximations, names the teams
/// as trademark holders of their respective owners, and disclaims any
/// affiliation with Formula 1 — supporting a nominative-fair-use posture.
final class AccentColorInfoViewController: NSViewController {
    private static let popoverWidth: CGFloat = 340
    private static let edgePadding: CGFloat = 16

    static let titleText = "About these colors"
    // Concatenated at runtime; the joined string is the key looked up in
    // Localizable.xcstrings so it must match the catalog entry exactly.
    static let bodyText = "Meridian is an independent project, built by an F1 fan, "
        + "not affiliated with, sponsored by, or endorsed by Formula 1 or any of the teams listed. "
        + "Team names are trademarks of their respective owners, used here only to identify the "
        + "livery colors they inspire. Colors are fan approximations, not official team colors."

    override func loadView() {
        let title = NSTextField(labelWithString: Self.titleText.localized())
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.textColor = NSColor.labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: Self.bodyText.localized())
        body.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        body.textColor = NSColor.secondaryLabelColor
        body.preferredMaxLayoutWidth = Self.popoverWidth - (Self.edgePadding * 2)
        body.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: Self.edgePadding,
                                        left: Self.edgePadding,
                                        bottom: Self.edgePadding,
                                        right: Self.edgePadding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.popoverWidth),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }
}
