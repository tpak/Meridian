// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLocation
import Combine
import CoreLoggerKit
import CoreModelKit

struct PanelConstants {
    static let modernSliderPointsInADay = 96
}

class ParentPanelController: NSWindowController {
    var cancellables = Set<AnyCancellable>()

    var dateFormatter = DateFormatter()

    var futureSliderValue: Int = 0

    var parentTimer: Repeater?

    var previousPopoverRow: Int = -1

    var additionalOptionsPopover: NSPopover?

    var datasource: TimezoneDataSource?

    var dataStore: DataStoring = DataStore.shared()

    private lazy var oneWindow: OneWindowController? = {
        let preferencesStoryboard = NSStoryboard(name: "Preferences", bundle: nil)
        return preferencesStoryboard.instantiateInitialController() as? OneWindowController
    }()

    @IBOutlet var mainTableView: PanelTableView!

    @IBOutlet var stackView: NSStackView!

    @IBOutlet var scrollViewHeight: NSLayoutConstraint!

    @IBOutlet var shutdownButton: NSButton!

    @IBOutlet var preferencesButton: NSButton!

    @IBOutlet var pinButton: NSButton!

    @IBOutlet var roundedDateView: NSView!

    // Modern Slider
    public var currentCenterIndexPath: Int = -1
    public var closestQuarterTimeRepresentation: Date?
    @IBOutlet var modernSlider: NSCollectionView!
    @IBOutlet var modernSliderLabel: NSTextField!
    @IBOutlet var modernContainerView: ModernSliderContainerView!
    @IBOutlet var goBackwardsButton: NSButton!
    @IBOutlet var goForwardButton: NSButton!
    @IBOutlet var resetModernSliderButton: NSButton!

    var defaultPreferences: [Data] {
        return dataStore.timezones()
    }

    deinit {
        datasource = nil
    }

    private func setupObservers() {
        UserDefaults.standard.publisher(for: \.displayFutureSlider)
            .receive(on: RunLoop.main)
            .sink { [weak self] changedValue in
                guard let self = self, let containerView = self.modernContainerView else { return }
                if changedValue == 0 {
                    containerView.isHidden = false
                } else {
                    containerView.isHidden = true
                }
            }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.userFontSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] newFontSize in
                Logger.log(object: ["FontSize": newFontSize], for: "User Font Size Preference")
                self?.mainTableView.reloadData()
                self?.setScrollViewConstraint()
            }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.sliderDayRange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.adjustFutureSliderBasedOnPreferences()
                self?.modernSlider?.reloadData()
            }
            .store(in: &cancellables)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        // Setup table
        mainTableView.backgroundColor = NSColor.clear
        mainTableView.selectionHighlightStyle = .none
        mainTableView.enclosingScrollView?.hasVerticalScroller = false
        mainTableView.style = .plain

        // Setup images using system symbols
        shutdownButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")!
        preferencesButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!
        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")!

        // Setup KVO observers for user default changes
        setupObservers()

        // Set the background color of the bottom buttons view to something different to indicate we're not in a release candidate
#if DEBUG
        stackView.arrangedSubviews.last?.layer?.backgroundColor = NSColor(deviceRed: 255.0 / 255.0,
                                                                          green: 150.0 / 255.0,
                                                                          blue: 122.0 / 255.0,
                                                                          alpha: 0.5).cgColor
        stackView.arrangedSubviews.last?.toolTip = "Debug Mode"
#endif

        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.systemTimezoneDidChange() }
            .store(in: &cancellables)

        // UI adjustments based on user preferences
        if dataStore.timezones().isEmpty || dataStore.shouldDisplay(.futureSlider) == false {

            if modernContainerView != nil {
                modernContainerView.isHidden = true
            }
        } else if let value = dataStore.retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber {
            if value.intValue == 1 {
                if modernContainerView != nil {
                    modernContainerView.isHidden = true
                }
            } else if value.intValue == 0 {
                if modernContainerView != nil {
                    modernContainerView.isHidden = false
                }
            }
        }

        // More UI adjustments
        adjustFutureSliderBasedOnPreferences()
        setupModernSliderIfNeccessary()
        if roundedDateView != nil {
            setupRoundedDateView()
        }
    }

    private func setupRoundedDateView() {
        roundedDateView.wantsLayer = true
        roundedDateView.layer?.cornerRadius = 12.0
        roundedDateView.layer?.masksToBounds = false
        roundedDateView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    @objc func systemTimezoneDidChange() {
        OperationQueue.main.addOperation {
            self.updateHomeObject(with: TimeZone.autoupdatingCurrent.identifier,
                                  coordinates: nil)
        }
    }

    private func updateHomeObject(with customLabel: String, coordinates: CLLocationCoordinate2D?) {
        let timezones = dataStore.timezones()

        var timezoneObjects: [TimezoneData] = []

        for timezone in timezones {
            if let model = TimezoneData.customObject(from: timezone) {
                timezoneObjects.append(model)
            }
        }

        for timezoneObject in timezoneObjects where timezoneObject.isSystemTimezone == true {
            timezoneObject.setLabel(customLabel)
            timezoneObject.formattedAddress = customLabel
            if let latlong = coordinates {
                timezoneObject.longitude = latlong.longitude
                timezoneObject.latitude = latlong.latitude
            }
        }

        var datas: [Data] = []

        for updatedObject in timezoneObjects {
            guard let dataObject = NSKeyedArchiver.clocker_archive(with: updatedObject) else {
                continue
            }
            datas.append(dataObject)
        }

        dataStore.setTimezones(datas)

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setupMenubarTimer()
        }
    }

    private func adjustFutureSliderBasedOnPreferences() {
        setTimezoneDatasourceSlider(sliderValue: 0)
        updateTableContent()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        additionalOptionsPopover = NSPopover()
    }

    func screenHeight() -> CGFloat {
        guard let main = NSScreen.main else { return 100 }

        let mouseLocation = NSEvent.mouseLocation

        var current = main.frame.height

        let activeScreens = NSScreen.screens.filter { current -> Bool in
            NSMouseInRect(mouseLocation, current.frame, false)
        }

        if let main = activeScreens.first {
            current = main.frame.height
        }

        return current
    }

    func invalidateMenubarTimer() {
        parentTimer = nil
    }

    private func getAdjustedRowHeight(for object: TimezoneData?, _ currentHeight: CGFloat) -> CGFloat {
        let userFontSize: NSNumber = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber ?? 4
        let shouldShowSunrise = dataStore.shouldDisplay(.sunrise)

        var newHeight = currentHeight

        if newHeight <= 68.0 {
            newHeight = 60.0
        }

        if newHeight >= 68.0 {
            newHeight = userFontSize == 4 ? 68.0 : 68.0
            if let note = object?.note, note.isEmpty == false {
                newHeight += 20
            } else if let obj = object,
                      TimezoneDataOperations(with: obj, store: dataStore).nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) != nil {
                newHeight += 20
            }
        }

        if newHeight >= 88.0 {
            // Set it to 90 expicity in case the row height is calculated be higher.
            newHeight = 88.0

            let ops = object.flatMap { TimezoneDataOperations(with: $0, store: dataStore) }
            if let note = object?.note, note.isEmpty,
               ops?.nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) == nil {
                newHeight -= 20.0
            }
        }

        if shouldShowSunrise, object?.selectionType == .city {
            newHeight += 8.0
        }

        if object?.isSystemTimezone == true {
            newHeight += 5
        }

        newHeight += mainTableView.intercellSpacing.height

        return newHeight
    }

    func setScrollViewConstraint() {
        var totalHeight: CGFloat = 0.0
        let preferences = defaultPreferences

        for cellIndex in 0 ..< preferences.count {
            let currentObject = TimezoneData.customObject(from: preferences[cellIndex])
            let rowRect = mainTableView.rect(ofRow: cellIndex)
            totalHeight += getAdjustedRowHeight(for: currentObject, rowRect.size.height)
        }

        // This is for the Add Cell View case
        if preferences.isEmpty {
            scrollViewHeight.constant = 100.0
            return
        }

        if let userFontSize = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber {
            if userFontSize == 4 {
                scrollViewHeight.constant = totalHeight + CGFloat(userFontSize.intValue * 2)
            } else {
                scrollViewHeight.constant = totalHeight + CGFloat(userFontSize.intValue * 2) * 3.0
            }
        }

        if scrollViewHeight.constant > (screenHeight() - 100) {
            scrollViewHeight.constant = (screenHeight() - 100)
        }

        if dataStore.shouldDisplay(.futureSlider) {
            let isModernSliderDisplayed = dataStore.retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber ?? 0
            if isModernSliderDisplayed == 0 {
                if scrollViewHeight.constant >= (screenHeight() - 200) {
                    scrollViewHeight.constant = (screenHeight() - 300)
                }
            } else {
                if scrollViewHeight.constant >= (screenHeight() - 200) {
                    scrollViewHeight.constant = (screenHeight() - 200)
                }
            }
        }
    }

    private lazy var menubarTitleHandler = MenubarTitleProvider(with: dataStore)

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .regular),
        .baselineOffset: 0.1
    ]

    @IBAction func openPreferences(_: NSButton) {
        updatePopoverDisplayState()
        openPreferencesWindow()
    }

    @IBAction func showMoreOptions(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        let menu = PanelContextMenu.build(target: self)
        NSMenu.popUpContextMenu(menu,
                                with: event,
                                for: sender)
    }

    @discardableResult
    func showNotesPopover(forRow row: Int, relativeTo _: NSRect, andButton target: NSButton!) -> Bool {
        let defaults = dataStore.timezones()

        guard let popover = additionalOptionsPopover else {
            Logger.info("Data was unexpectedly nil")
            return false
        }

        var correctRow = row

        target.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Options")!

        popover.animates = true

        // Found a case where row number was 8 but we had only 2 timezones
        if correctRow >= defaults.count {
            correctRow = defaults.count - 1
        }

        return true
    }

    func dismissRowActions() {
        mainTableView.rowActionsVisible = false
    }

    // If the popover is displayed, close it
    // Called when preferences are going to be displayed!
    func updatePopoverDisplayState() {
        additionalOptionsPopover = nil
    }
}

// MARK: - Data & Table Updates

extension ParentPanelController {
    func updateDefaultPreferences() {
        PerfLogger.startMarker("Update Default Preferences")

        updatePanelColor()

        let defaults = dataStore.timezones()
        let convertedTimezones = defaults.map { data -> TimezoneData in
            TimezoneData.customObject(from: data)!
        }

        datasource = TimezoneDataSource(items: convertedTimezones, store: dataStore)
        mainTableView.dataSource = datasource
        mainTableView.delegate = datasource
        mainTableView.panelDelegate = datasource

        updateDatasource(with: convertedTimezones)

        PerfLogger.endMarker("Update Default Preferences")
    }

    func updateDatasource(with timezones: [TimezoneData]) {
        datasource?.setItems(items: timezones)
        datasource?.setSlider(value: futureSliderValue)

        if let userFontSize = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber {
            scrollViewHeight.constant = CGFloat(timezones.count) * (mainTableView.rowHeight + CGFloat(userFontSize.floatValue * 1.5))

            setScrollViewConstraint()

            mainTableView.reloadData()
        }
    }

    func updatePanelColor() {
        window?.alphaValue = 1.0
    }

    func setTimezoneDatasourceSlider(sliderValue: Int) {
        futureSliderValue = sliderValue
        datasource?.setSlider(value: sliderValue)
    }

    func deleteTimezone(at row: Int) {
        var defaults = defaultPreferences

        // Remove from panel
        defaults.remove(at: row)
        dataStore.setTimezones(defaults)
        updateDefaultPreferences()

        NotificationCenter.default.post(name: Notification.Name.customLabelChanged,
                                        object: nil)

        // Now log!
        Logger.log(object: nil, for: "Deleted Timezone Through Swipe")
    }

    private func updateMenubarDisplay() {
        guard let status = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else { return }
        if dataStore.shouldDisplay(.menubarCompactMode) {
            status.updateCompactMenubar()
        } else {
            let title = menubarTitleHandler.titleForMenubar() ?? ""
            status.statusItem.button?.attributedTitle = NSAttributedString(
                string: title,
                attributes: ParentPanelController.attributes
            )
        }
    }

    @objc func updateTime() {
        if (dataStore.menubarTimezones()?.count ?? 0) >= 1 {
            updateMenubarDisplay()
        }

        let preferences = dataStore.timezones()

        if modernSlider != nil, modernSlider.isHidden == false, modernContainerView.currentlyInFocus == false {
            if currentCenterIndexPath != -1, currentCenterIndexPath != modernSlider.numberOfItems(inSection: 0) / 2 {
                // User is currently scrolling, return!
                return
            }
        }

        let hoverRow = mainTableView.hoverRow
        stride(from: 0, to: preferences.count, by: 1).forEach {
            let current = preferences[$0]

            if $0 < mainTableView.numberOfRows,
               let cellView = mainTableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? TimezoneCellView,
               let model = TimezoneData.customObject(from: current) {
                if modernContainerView != nil, modernSlider.isHidden == false, modernContainerView.currentlyInFocus {
                    return
                }

                let dataOperation = TimezoneDataOperations(with: model, store: dataStore)
                cellView.time.stringValue = dataOperation.time(with: futureSliderValue)
                cellView.sunriseSetTime.stringValue = dataOperation.formattedSunriseTime(with: futureSliderValue)
                cellView.sunriseSetTime.lineBreakMode = .byClipping

                if $0 != hoverRow {
                    cellView.relativeDate.stringValue = dataOperation.date(with: futureSliderValue, displayType: .panel)
                }

                cellView.currentLocationIndicator.isHidden = !model.isSystemTimezone
                cellView.sunriseImage.image = model.isSunriseOrSunset
                    ? NSImage(systemSymbolName: "sunrise.fill", accessibilityDescription: "Sunrise")!
                    : NSImage(systemSymbolName: "sunset.fill", accessibilityDescription: "Sunset")!
                cellView.sunriseImage.contentTintColor = model.isSunriseOrSunset ? NSColor.systemYellow : NSColor.systemOrange
                if let note = model.note, !note.isEmpty {
                    cellView.noteLabel.stringValue = note
                } else if let value = TimezoneDataOperations(with: model, store: dataStore).nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) {
                    cellView.noteLabel.stringValue = value
                } else {
                    cellView.noteLabel.stringValue = UserDefaultKeys.emptyString
                }
                cellView.layout(with: model)
            }
        }
    }

    @objc func updateTableContent() {
        mainTableView.reloadData()
    }
}

// MARK: - Actions

extension ParentPanelController {
    @objc func openPreferencesWindow() {
        oneWindow?.openGeneralPane()
    }

    func minutes(from date: Date, other: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: other).minute ?? 0
    }

    @objc dynamic func terminateClocker() {
        NSApplication.shared.terminate(nil)
    }

    @objc func reportIssue() {
        guard let url = URL(string: AboutUsConstants.GitHubIssuesURL) else { return }
        NSWorkspace.shared.open(url)

        if let countryCode = Locale.autoupdatingCurrent.region?.identifier {
            let custom: [String: Any] = ["Country": countryCode]
            Logger.log(object: custom, for: "Report Issue Opened")
        }
    }

    @objc func rate() {
        guard let sourceURL = URL(string: AboutUsConstants.AppStoreLink) else { return }

        NSWorkspace.shared.open(sourceURL)
    }

    @objc func openFAQs() {
        guard let sourceURL = URL(string: AboutUsConstants.FAQsLink) else { return }

        NSWorkspace.shared.open(sourceURL)
    }
}

extension ParentPanelController: NSPopoverDelegate {
    func popoverShouldClose(_: NSPopover) -> Bool {
        return false
    }
}
