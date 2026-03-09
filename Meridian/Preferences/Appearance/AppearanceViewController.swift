// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

class AppearanceViewController: ParentViewController {
    @IBOutlet var timeFormat: NSPopUpButton!
    @IBOutlet var theme: NSPopUpButton!
    @IBOutlet var informationLabel: NSTextField!
    @IBOutlet var sliderDayRangePopup: NSPopUpButton!
    @IBOutlet var visualEffectView: NSVisualEffectView!
    @IBOutlet var menubarMode: NSSegmentedControl!
    @IBOutlet var includeDayInMenubarControl: NSSegmentedControl!
    @IBOutlet var includeDateInMenubarControl: NSSegmentedControl!
    @IBOutlet var includePlaceNameControl: NSSegmentedControl!
    @IBOutlet var appearanceTab: NSTabView!
    @IBOutlet var appDisplayControl: NSSegmentedControl!

    private var previewTimezones: [TimezoneData] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        informationLabel.stringValue = "Favourite a timezone to enable menubar display options.".localized()
        informationLabel.textColor = NSColor.secondaryLabelColor
        informationLabel.setAccessibilityIdentifier("InformationLabel")

        setupTimeFormatPopup()

        sliderDayRangePopup.removeAllItems()
        sliderDayRangePopup.addItems(withTitles: (1...7).map { $0 == 1 ? "1 day" : "\($0) days" })

        setup()

        previewTimezones = [TimezoneData(with: ["customLabel": "San Francisco",
                                                "formattedAddress": "San Francisco",
                                                "place_id": "TestIdentifier",
                                                "timezoneID": "America/Los_Angeles",
                                                "nextUpdate": "",
                                                "note": "Your individual note about this location goes here!",
                                                "latitude": "37.7749295",
                                                "longitude": "-122.4194155"])]

        appearanceTab.selectTabViewItem(at: 0)

        previewPanelTableView.dataSource = self
        previewPanelTableView.delegate = self
        previewPanelTableView.reloadData()
        previewPanelTableView.selectionHighlightStyle = .none
        previewPanelTableView.enclosingScrollView?.hasVerticalScroller = false
        previewPanelTableView.enclosingScrollView?.wantsLayer = true
        previewPanelTableView.enclosingScrollView?.layer?.cornerRadius = 12
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
        timeFormat.item(at: 2)?.isEnabled = false
        timeFormat.item(at: 5)?.isEnabled = false
        timeFormat.item(at: 8)?.isEnabled = false
        timeFormat.autoenablesItems = false
        timeFormat.selectItem(at: dataStore.timezoneFormat().intValue)
        timeFormat.setAccessibilityIdentifier("TimeFormatPopover")
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        if let menubarFavourites = dataStore.menubarTimezones() {
            visualEffectView.isHidden = menubarFavourites.isEmpty ? false : true
            informationLabel.isHidden = menubarFavourites.isEmpty ? false : true
        }

        if let selectedIndex = dataStore.retrieve(key: UserDefaultKeys.futureSliderRange) as? NSNumber {
            sliderDayRangePopup.selectItem(at: selectedIndex.intValue)
        }

        let shouldDisplayCompact = dataStore.shouldDisplay(.menubarCompactMode)
        menubarMode.setSelected(true, forSegment: shouldDisplayCompact ? 0 : 1)

        // True is Menubar Only and False is Menubar + Dock
        let appDisplayOptions = dataStore.shouldDisplay(.appDisplayOptions)
        appDisplayControl.setSelected(true, forSegment: appDisplayOptions ? 0 : 1)
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
    @IBOutlet var menubarModeLabel: NSTextField!
    @IBOutlet var previewLabel: NSTextField!
    @IBOutlet var miscelleaneousLabel: NSTextField!

    // Panel Preview
    @IBOutlet var previewPanelTableView: NSTableView!

    private func setup() {
        timeFormatLabel.stringValue = "Time Format".localized()
        panelTheme.stringValue = "Panel Theme".localized()
        dayDisplayOptionsLabel.stringValue = "Day Display Options".localized()
        showSliderLabel.stringValue = "Time Scroller".localized()
        showSunriseLabel.stringValue = "Show Sunrise/Sunset".localized()
        largerTextLabel.stringValue = "Larger Text".localized()
        futureSliderRangeLabel.stringValue = "Future Slider Range".localized()
        includeDateLabel.stringValue = "Include Date".localized()
        includeDayLabel.stringValue = "Include Day".localized()
        includePlaceLabel.stringValue = "Include Place Name".localized()
        menubarModeLabel.stringValue = "Menubar Mode".localized()
        previewLabel.stringValue = "Preview".localized()
        miscelleaneousLabel.stringValue = "Miscellaneous".localized()

        [timeFormatLabel, panelTheme,
         dayDisplayOptionsLabel, showSliderLabel,
         showSunriseLabel, largerTextLabel, futureSliderRangeLabel,
         includeDayLabel, includeDateLabel, includePlaceLabel, appDisplayLabel, menubarModeLabel,
         previewLabel, miscelleaneousLabel].forEach {
            $0?.textColor = NSColor.labelColor
        }

        previewPanelTableView.backgroundColor = NSColor.windowBackgroundColor
    }

    @IBAction func timeFormatSelectionChanged(_ sender: NSPopUpButton) {
        let selection = NSNumber(value: sender.indexOfSelectedItem)

        UserDefaults.standard.set(selection, forKey: UserDefaultKeys.selectedTimeZoneFormatKey)
        refresh(panel: true)

        if let selectedFormat = sender.selectedItem?.title,
           selectedFormat.contains("ss") {
            Logger.info("Selected format contains timezone format")
            guard let panelController = PanelController.panel() else { return }
            panelController.pauseTimer()
        }

        updateStatusItem()
        previewPanelTableView.reloadData()
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
            Logger.log(object: ["themeSelected": "Light"], for: "Theme")
        case 1:
            Logger.log(object: ["themeSelected": "Dark"], for: "Theme")
        case 2:
            Logger.log(object: ["themeSelected": "System"], for: "Theme")
        default:
            Logger.log(object: ["themeSelected": "System"], for: "Theme")
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
        Logger.log(object: ["dayPreference": loggingStringForRelativeDisplaySelection(sender.selectedSegment)], for: "RelativeDate")

        refresh(panel: true)

        previewPanelTableView.reloadData()
    }

    @IBAction func showFutureSlider(_: Any) {
        refresh(panel: false)
    }

    @IBAction func showSunriseSunset(_ sender: NSSegmentedControl) {
        Logger.log(object: ["Is It Displayed": sender.selectedSegment == 0 ? "YES" : "NO"], for: "Sunrise Sunset")
        refresh(panel: true)
        previewPanelTableView.reloadData()
    }

    @IBAction func changeAppDisplayOptions(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            Logger.log(object: ["Selection": "Menubar"], for: "Dock Mode")
            NSApp.setActivationPolicy(.accessory)
        } else {
            Logger.log(object: ["Selection": "Menubar and Dock"], for: "Dock Mode")
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func refresh(panel: Bool) {
        OperationQueue.main.addOperation {
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

    @IBAction func displayDayInMenubarAction(_: Any) {
        updateStatusItem()
    }

    @IBAction func displayDateInMenubarAction(_: Any) {
        updateStatusItem()
    }

    @IBAction func displayPlaceInMenubarAction(_: Any) {
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let statusItem = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else {
            return
        }

        if dataStore.shouldDisplay(.menubarCompactMode) {
            statusItem.setupStatusItem()
        } else {
            statusItem.refresh()
        }
    }

    @IBAction func menubarModeChanged(_ sender: NSSegmentedControl) {
        guard let statusItem = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else {
            return
        }

        statusItem.setupStatusItem()

        if sender.selectedSegment == 0 {
            Logger.log(object: ["Context": "In Appearance View"], for: "Switched to Compact Mode")
        } else {
            Logger.log(object: ["Context": "In Appearance View"], for: "Switched to Standard Mode")
        }
    }

    @IBAction func fontSliderChanged(_: Any) {
        previewPanelTableView.reloadData()
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
            Logger.info("Unable to create tableviewcell")
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
        if let note = currentModel.note, !note.isEmpty {
            cellView.noteLabel.stringValue = note
        } else {
            cellView.noteLabel.stringValue = UserDefaultKeys.emptyString
        }
        cellView.currentLocationIndicator.isHidden = !currentModel.isSystemTimezone
        cellView.time.setAccessibilityIdentifier("ActualTime")
        cellView.layout(with: currentModel)

        cellView.setAccessibilityIdentifier(currentModel.formattedTimezoneLabel())
        cellView.setAccessibilityLabel(currentModel.formattedTimezoneLabel())

        return cellView
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let userFontSize = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber, previewTimezones.count > row {
            let model = previewTimezones[row]

            let rowHeight: Int = userFontSize == 4 ? 60 : 65
            if let note = model.note, !note.isEmpty {
                return CGFloat(rowHeight + userFontSize.intValue + 25)
            }

            return CGFloat(rowHeight + (userFontSize.intValue * 2))
        }

        return 0
    }
}
