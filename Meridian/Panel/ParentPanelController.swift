// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLocation
import Combine
import CoreLoggerKit
import CoreModelKit

struct PanelConstants {
    static let modernSliderPointsInADay = 96
    static let minutesPerSliderPoint = 15
}

private enum FutureSliderDisplayState: Int {
    case visible = 0
    case hidden = 1
}

class ParentPanelController: NSWindowController {
    var cancellables = Set<AnyCancellable>()

    var futureSliderValue: Int = 0

    var parentTimer: Repeater?

    var previousPopoverRow: Int = -1

    var additionalOptionsPopover: NSPopover?

    var datasource: TimezoneDataSource?

    var dataStore: DataStoring = DataStore.shared()

    lazy var timeScrollerViewModel: TimeScrollerViewModel = {
        return TimeScrollerViewModel(dataStore: dataStore)
    }()

    lazy var oneWindow: OneWindowController? = {
        let preferencesStoryboard = NSStoryboard(name: "Preferences", bundle: nil)
        return preferencesStoryboard.instantiateInitialController() as? OneWindowController
    }()

    @IBOutlet var mainTableView: PanelTableView!

    @IBOutlet var stackView: NSStackView!

    @IBOutlet var scrollViewHeight: NSLayoutConstraint!

    @IBOutlet var settingsButton: NSButton!

    @IBOutlet var versionStatusLabel: NSTextField!

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
        NotificationCenter.default.removeObserver(self)
        datasource = nil
    }

    private func setupObservers() {
        UserDefaults.standard.publisher(for: \.displayFutureSlider)
            .receive(on: RunLoop.main)
            .sink { [weak self] changedValue in
                guard let self = self, let containerView = self.modernContainerView else { return }
                let state = FutureSliderDisplayState(rawValue: changedValue)
                containerView.isHidden = (state == .hidden)
            }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.userFontSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] newFontSize in
                Logger.debug("User Font Size Preference: \(newFontSize)")
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

        // Setup settings button
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")

        // Setup copy-all button next to settings button
        setupCopyAllButton()

        // Setup version label
        updateVersionStatusLabel()

        // Setup KVO observers for user default changes
        setupObservers()

        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.systemTimezoneDidChange() }
            .store(in: &cancellables)

        // UI adjustments based on user preferences
        if let containerView = modernContainerView {
            if dataStore.timezones().isEmpty || dataStore.shouldDisplay(.futureSlider) == false {
                containerView.isHidden = true
            } else {
                configureSliderVisibility(containerView: containerView)
            }
        }

        // More UI adjustments
        adjustFutureSliderBasedOnPreferences()
        setupModernSliderIfNeccessary()
        if roundedDateView != nil {
            setupRoundedDateView()
        }
    }

    private func configureSliderVisibility(containerView: ModernSliderContainerView) {
        guard let futureSliderValue = dataStore.retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber else {
            containerView.isHidden = true
            return
        }
        containerView.isHidden = (futureSliderValue.intValue == FutureSliderDisplayState.hidden.rawValue)
    }

    private func setupRoundedDateView() {
        roundedDateView.wantsLayer = true
        roundedDateView.layer?.cornerRadius = 12.0
        roundedDateView.layer?.masksToBounds = false
        roundedDateView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    private func setupCopyAllButton() {
        guard let footer = settingsButton?.superview else { return }

        // Detach the version label's leading from the settings button so we can insert the copy button between them.
        let oldLeading = footer.constraints.first {
            $0.firstItem === versionStatusLabel && $0.firstAttribute == .leading &&
            $0.secondItem === settingsButton && $0.secondAttribute == .trailing
        }
        oldLeading?.isActive = false

        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy All Timezones")
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = "Copy all timezones to clipboard"
        btn.target = self
        btn.action = #selector(copyAllTimezonesToClipboard)
        footer.addSubview(btn)

        NSLayoutConstraint.activate([
            btn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            btn.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: 4),
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22),
            versionStatusLabel.leadingAnchor.constraint(equalTo: btn.trailingAnchor, constant: 4)
        ])
    }

    func updateVersionStatusLabel() {
        guard versionStatusLabel != nil else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        versionStatusLabel.stringValue = "v\(version)"
    }

    @objc func systemTimezoneDidChange() {
        OperationQueue.main.addOperation {
            self.updateHomeObject(with: TimeZone.autoupdatingCurrent.identifier,
                                  coordinates: nil)
        }
    }

    private func updateHomeObject(with customLabel: String, coordinates: CLLocationCoordinate2D?) {
        let objects = dataStore.timezoneObjects()

        for object in objects where object.isSystemTimezone {
            object.setLabel(customLabel)
            object.formattedAddress = customLabel
            if let latlong = coordinates {
                object.longitude = latlong.longitude
                object.latitude = latlong.latitude
            }
        }

        let datas = objects.compactMap { NSKeyedArchiver.secureArchive(with: $0) }
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

    func invalidateMenubarTimer() {
        parentTimer = nil
    }

    private lazy var menubarTitleHandler = MenubarTitleProvider(with: dataStore)

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .regular),
        .baselineOffset: 0.1
    ]

    @IBAction func showSettingsMenu(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        let menu = PanelContextMenu.build(target: self)
        NSMenu.popUpContextMenu(menu,
                                with: event,
                                for: sender)
    }

    @discardableResult
    func showNotesPopover(forRow row: Int, relativeTo _: NSRect, andButton target: NSButton!) -> Bool {
        guard let target = target else { return false }

        let defaults = dataStore.timezones()

        guard let popover = additionalOptionsPopover else {
            Logger.debug("Data was unexpectedly nil")
            return false
        }

        var correctRow = row

        target.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Options")

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

        let convertedTimezones = dataStore.timezoneObjects()

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
        Logger.debug("Deleted Timezone Through Swipe")
    }

    private func updateMenubarDisplay() {
        guard let status = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else { return }
        if dataStore.shouldDisplay(.menubarCompactMode) {
            status.updateCompactMenubar()
        } else {
            let title = menubarTitleHandler.titleForMenubar()
            status.statusItem.button?.attributedTitle = NSAttributedString(
                string: title,
                attributes: ParentPanelController.attributes
            )
        }
    }

    @objc func updateTime() {
        if dataStore.menubarTimezones().count >= 1 {
            updateMenubarDisplay()
        }

        let timezones = dataStore.timezoneObjects()

        if modernSlider != nil, modernSlider.isHidden == false, modernContainerView.currentlyInFocus == false {
            if currentCenterIndexPath != -1, currentCenterIndexPath != modernSlider.numberOfItems(inSection: 0) / 2 {
                // User is currently scrolling, return!
                return
            }
        }

        let hoverRow = mainTableView.hoverRow
        stride(from: 0, to: timezones.count, by: 1).forEach { index in
            let model = timezones[index]

            guard index < mainTableView.numberOfRows,
                  let cellView = mainTableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? TimezoneCellView else { return }

            updateCell(cellView, with: model, at: index, hoverRow: hoverRow)
        }
    }

    private func updateCell(_ cellView: TimezoneCellView, with model: TimezoneData, at index: Int, hoverRow: Int) {
        if modernContainerView != nil, modernSlider.isHidden == false, modernContainerView.currentlyInFocus {
            return
        }

        let dataOperation = TimezoneDataOperations(with: model, store: dataStore)
        if !cellView.isEditingTime {
            cellView.time.stringValue = dataOperation.time(with: futureSliderValue)
        }
        cellView.sunriseSetTime.stringValue = dataOperation.formattedSunriseTime(with: futureSliderValue)
        cellView.sunriseSetTime.lineBreakMode = .byClipping

        if index != hoverRow {
            cellView.relativeDate.stringValue = dataOperation.date(with: futureSliderValue, displayType: .panel)
        }

        cellView.currentLocationIndicator.isHidden = !model.isSystemTimezone
        cellView.sunriseImage.image = model.isSunriseOrSunset
            ? NSImage(systemSymbolName: "sunrise.fill", accessibilityDescription: "Sunrise")
            : NSImage(systemSymbolName: "sunset.fill", accessibilityDescription: "Sunset")
        cellView.sunriseImage.contentTintColor = model.isSunriseOrSunset ? NSColor.systemYellow : NSColor.systemOrange
        if let note = model.note, !note.isEmpty {
            cellView.noteLabel.stringValue = note
        } else if let value = dataOperation.nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) {
            cellView.noteLabel.stringValue = value
        } else {
            cellView.noteLabel.stringValue = UserDefaultKeys.emptyString
        }
        cellView.layout(with: model)
    }

    @objc func updateTableContent() {
        mainTableView.reloadData()
    }
}

extension ParentPanelController: NSPopoverDelegate {
    func popoverShouldClose(_: NSPopover) -> Bool {
        return false
    }
}
