// Copyright © 2015 Abhishek Banthia

import Cocoa
import Combine
import CoreLoggerKit
import CoreModelKit

struct PreferencesConstants {
    static let noTimezoneSelectedErrorMessage = NSLocalizedString("No Timezone Selected",
                                                                  comment: "Message shown when the user taps on Add without selecting a timezone")
    static let maxTimezonesErrorMessage = NSLocalizedString("Max Timezones Selected",
                                                            comment: "Max Timezones Error Message")
    static let maxCharactersAllowed = NSLocalizedString("Max Search Characters",
                                                        comment: "Max Character Count Allowed Error Message")
    static let noInternetConnectivityError = "You're offline, maybe?".localized()
    static let tryAgainMessage = "Try again, maybe?".localized()
    static let offlineErrorMessage = "The Internet connection appears to be offline.".localized()
    static let hotKeyPathIdentifier = "values.globalPing"
}

class PreferencesViewController: ParentViewController {
    @IBOutlet var placeholderLabel: NSTextField!
    @IBOutlet var timezoneTableView: NSTableView!
    @IBOutlet var availableTimezoneTableView: NSTableView!
    @IBOutlet var timezonePanel: CustomPanel!
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

    @IBOutlet private var tableview: NSView!
    @IBOutlet private var additionalSortOptions: NSView!
    @IBOutlet var startAtLoginLabel: NSTextField!

    @IBOutlet var startupCheckbox: NSButton!

    // Sorting
    private var arePlacesSortedInAscendingOrder = false
    private let sortingManager = TimezoneSortingManager()

    private var selectedTimeZones: [Data] {
        return dataStore.timezones()
    }

    private var cancellables = Set<AnyCancellable>()
    // Selected Timezones Data Source
    private var selectionsDataSource: PreferencesDataSource!
    // Search Results Data Source Handler
    var searchResultsDataSource: SearchDataSource!
    private lazy var startupManager = StartupManager()

    private lazy var notimezoneView: NoTimezoneView? = NoTimezoneView(frame: tableview.frame)

    private var timezoneAdditionHandler: TimezoneAdditionHandler!

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.publisher(for: .customLabelChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshTimezoneTableView() }
            .store(in: &cancellables)

        refreshTimezoneTableView()

        setup()

        setupShortcutObserver()

        searchField.placeholderString = "Enter city, state, country or timezone name"

        selectionsDataSource = PreferencesDataSource(with: dataStore, callbackDelegate: self)
        timezoneTableView.dataSource = selectionsDataSource
        timezoneTableView.delegate = selectionsDataSource

        searchResultsDataSource = SearchDataSource(with: searchField)
        availableTimezoneTableView.dataSource = searchResultsDataSource
        availableTimezoneTableView.delegate = searchResultsDataSource

        timezoneAdditionHandler = TimezoneAdditionHandler(host: self, dataStore: dataStore)
    }

    private func setupLocalizedText() {
        startAtLoginLabel.stringValue = NSLocalizedString("Start at Login",
                                                          comment: "Start at Login")
        timezoneSortButton.title = NSLocalizedString("Sort by Time Difference",
                                                     comment: "Start at Login")
        timezoneNameSortButton.title = NSLocalizedString("Sort by Name",
                                                         comment: "Start at Login")
        labelSortButton.title = NSLocalizedString("Sort by Label",
                                                  comment: "Start at Login")
        addButton.title = NSLocalizedString("Add Button Title",
                                            comment: "Button to add a location")
        closeButton.title = NSLocalizedString("Close Button Title",
                                              comment: "Button to close the panel")
    }

    @objc func refreshTimezoneTableView(_ shouldSelectNewlyInsertedTimezone: Bool = false) {
        OperationQueue.main.addOperation {
            self.build(shouldSelectNewlyInsertedTimezone)
        }
    }

    func refreshMainTable() {
        OperationQueue.main.addOperation {
            self.refresh()
        }
    }

    private func refresh() {
        guard let panel = PanelController.panel() else { return }
        panel.updateDefaultPreferences()
        panel.updateTableContent()
    }

    private func build(_ shouldSelectLastRow: Bool = false) {
        if dataStore.timezones() == [] {
            housekeeping()
            return
        }

        if selectedTimeZones.isEmpty == false {
            additionalSortOptions.isHidden = false
            if tableview.subviews.count > 1, let zeroView = notimezoneView, tableview.subviews.contains(zeroView) {
                zeroView.removeFromSuperview()
                timezoneTableView.enclosingScrollView?.isHidden = false
            }
            timezoneTableView.reloadData()
            if shouldSelectLastRow {
                timezoneAdditionHandler.selectNewlyInsertedTimezone()
            }
        } else {
            housekeeping()
        }

        cleanup()
    }

    private func housekeeping() {
        timezoneTableView.enclosingScrollView?.isHidden = true
        showNoTimezoneState()
        cleanup()
    }

    private func cleanup() {
        updateMenubarTitles() // Update the menubar titles, the custom labels might have changed.
    }

    private func updateMenubarTitles() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setupMenubarTimer()
        }
    }

    private func setup() {
        setupAccessibilityIdentifiers()

        deleteButton.isEnabled = false

        [placeholderLabel].forEach { $0.isHidden = true }

        messageLabel.stringValue = UserDefaultKeys.emptyString

        timezoneTableView.registerForDraggedTypes([.dragSession])

        progressIndicator.usesThreadedAnimation = true

        setupLocalizedText()

        setupColor()

        startupCheckbox.integerValue = dataStore.retrieve(key: UserDefaultKeys.startAtLogin) as? Int ?? 0

        searchField.bezelStyle = .roundedBezel
    }

    private func setupColor() {
        startAtLoginLabel.textColor = NSColor.labelColor

        [timezoneNameSortButton, labelSortButton, timezoneSortButton].forEach {
            $0?.attributedTitle = NSAttributedString(string: $0?.title ?? UserDefaultKeys.emptyString, attributes: [
                NSAttributedString.Key.foregroundColor: NSColor.labelColor,
                NSAttributedString.Key.font: NSFont(name: "Avenir-Light", size: 13) ?? NSFont.systemFont(ofSize: 13)
            ])
        }

        timezoneTableView.backgroundColor = NSColor.windowBackgroundColor
        availableTimezoneTableView.backgroundColor = NSColor.textBackgroundColor
        timezonePanel.backgroundColor = NSColor.textBackgroundColor
        timezonePanel.contentView?.wantsLayer = true
        timezonePanel.contentView?.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        addTimezoneButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        deleteButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
    }

    private func setupShortcutObserver() {
        recorderControl.setAccessibilityElement(true)
        recorderControl.setAccessibilityIdentifier("ShortcutControl")
        recorderControl.setAccessibilityLabel("ShortcutControl")
        recorderControl.updateDisplay()
        recorderControl.shortcutDidChange = { keyCombo in
            GlobalShortcutMonitor.shared.currentShortcut = keyCombo
        }
    }

    private func showNoTimezoneState() {
        if let zeroView = notimezoneView {
            notimezoneView?.wantsLayer = true
            tableview.addSubview(zeroView)
            Logger.log(object: ["Showing Empty View": "YES"], for: "Showing Empty View")
        }
        additionalSortOptions.isHidden = true
    }

    private func setupAccessibilityIdentifiers() {
        timezoneTableView.setAccessibilityIdentifier("TimezoneTableView")
        availableTimezoneTableView.setAccessibilityIdentifier("AvailableTimezoneTableView")
        searchField.setAccessibilityIdentifier("AvailableSearchField")
        timezoneSortButton.setAccessibility("SortByDifference")
        labelSortButton.setAccessibility("SortByLabelButton")
        timezoneNameSortButton.setAccessibility("SortByTimezoneName")
    }

    override var acceptsFirstResponder: Bool {
        return true
    }
}

extension PreferencesViewController: NSTableViewDataSource, NSTableViewDelegate {
    private func _markAsFavorite(_ dataObject: TimezoneData) {
        if dataObject.customLabel != nil {
            Logger.log(object: ["label": dataObject.customLabel ?? "Error"], for: "favouriteSelected")
        }

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setupMenubarTimer()
        }

        if let menubarTimezones = dataStore.menubarTimezones(), menubarTimezones.count > 1 {
            showAlertIfMoreThanOneTimezoneHasBeenAddedToTheMenubar()
        }
    }

    private func _unfavourite(_ dataObject: TimezoneData) {
        Logger.log(object: ["label": dataObject.customLabel ?? "Error"],
                   for: "favouriteRemoved")

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let menubarFavourites = dataStore.menubarTimezones(),
           menubarFavourites.isEmpty {
            appDelegate.invalidateMenubarTimer(true)
        }

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setupMenubarTimer()
        }
    }

    private func showAlertIfMoreThanOneTimezoneHasBeenAddedToTheMenubar() {
        let isUITestRunning = ProcessInfo.processInfo.arguments.contains(UserDefaultKeys.testingLaunchArgument)

        // If we have seen displayed the message before, abort!
        let haveWeSeenThisMessageBefore = UserDefaults.standard.bool(forKey: UserDefaultKeys.longStatusBarWarningMessage)

        if haveWeSeenThisMessageBefore, !isUITestRunning {
            return
        }

        // If the user is already using the compact mode, abort.
        if DataStore.shared().shouldDisplay(.menubarCompactMode), !isUITestRunning {
            return
        }

        // Time to display the alert.
        NSApplication.shared.activate(ignoringOtherApps: true)

        let infoText = """
        Multiple timezones occupy space and if macOS determines Meridian is occupying too much space, it'll hide Meridian entirely!
        Enable Menubar Compact Mode to fit in more timezones in less space.
        """

        let alert = NSAlert()
        alert.showsSuppressionButton = true
        alert.messageText = "More than one location added to the menubar 😅"
        alert.informativeText = infoText
        alert.addButton(withTitle: "Enable Compact Mode")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response.rawValue == 1000 {
            OperationQueue.main.addOperation {
                UserDefaults.standard.set(0, forKey: UserDefaultKeys.menubarCompactMode)

                if alert.suppressionButton?.state == NSControl.StateValue.on {
                    UserDefaults.standard.set(true, forKey: UserDefaultKeys.longStatusBarWarningMessage)
                }

                self.updateStatusBarAppearance()

                Logger.log(object: ["Context": ">1 Menubar Timezone in Preferences"], for: "Switched to Compact Mode")
            }
        }
    }
}

// MARK: - IBActions forwarded to TimezoneAdditionHandler

extension PreferencesViewController {
    @IBAction func addTimeZone(_: NSButton) {
        searchResultsDataSource.cleanupFilterArray()
        view.window?.beginSheet(timezonePanel,
                                completionHandler: nil)
    }

    @IBAction func addToFavorites(_: NSButton) {
        timezoneAdditionHandler.addToFavorites()
    }

    @IBAction func closePanel(_: NSButton) {
        timezoneAdditionHandler.closePanel()
    }

    @IBAction func filterArray(_: Any?) {
        timezoneAdditionHandler.filterArray()
    }

    @IBAction func removeFromFavourites(_: NSButton) {
        // If the user is editing a row, and decides to delete the row then we have a crash
        if timezoneTableView.editedRow != -1 || timezoneTableView.editedColumn != -1 {
            return
        }

        if timezoneTableView.selectedRow == -1, selectedTimeZones.count <= timezoneTableView.selectedRow {
            Logger.info("Data was unexpectedly nil")
            return
        }

        var newDefaults = selectedTimeZones

        let objectsToRemove = timezoneTableView.selectedRowIndexes.map { index -> Data in
            selectedTimeZones[index]
        }

        newDefaults = newDefaults.filter { !objectsToRemove.contains($0) }

        DataStore.shared().setTimezones(newDefaults)

        timezoneTableView.reloadData()

        refreshTimezoneTableView()

        refreshMainTable()

        updateStatusBarAppearance()

        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let statusItem = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else {
            return
        }

        statusItem.refresh()
    }

    private func updateStatusBarAppearance() {
        guard let statusItem = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() else {
            return
        }

        statusItem.setupStatusItem()
    }
}

extension PreferencesViewController {
    @IBAction func loginPreferenceChanged(_ sender: NSButton) {
        startupManager.toggleLogin(sender.state == .on)
    }
}

// Sorting
extension PreferencesViewController {
    @IBAction func sortOptions(_: NSButton) {
        additionalSortOptions.isHidden.toggle()
    }

    @IBAction func sortByTime(_ sender: NSButton) {
        let result = sortingManager.sort(selectedTimeZones, by: .time)
        sender.image = result.indicatorImage
        DataStore.shared().setTimezones(result.sorted)
        updateAfterSorting()
    }

    @IBAction func sortByLabel(_ sender: NSButton) {
        let result = sortingManager.sort(selectedTimeZones, by: .label)
        sender.image = result.indicatorImage
        DataStore.shared().setTimezones(result.sorted)
        updateAfterSorting()
    }

    @IBAction func sortByFormattedAddress(_ sender: NSButton) {
        let result = sortingManager.sort(selectedTimeZones, by: .name)
        sender.image = result.indicatorImage
        DataStore.shared().setTimezones(result.sorted)
        updateAfterSorting()
    }

    private func updateAfterSorting() {
        let newDefaults = selectedTimeZones
        DataStore.shared().setTimezones(newDefaults)
        refreshTimezoneTableView()
        refreshMainTable()
    }
}

// Helpers
extension PreferencesViewController {
    private func insert(timezone: TimezoneData, at index: Int) {
        guard let encodedObject = NSKeyedArchiver.clocker_archive(with: timezone) else {
            return
        }
        var newDefaults = selectedTimeZones
        newDefaults[index] = encodedObject
        DataStore.shared().setTimezones(newDefaults)
    }
}

extension PreferencesViewController: PreferenceSelectionUpdates {
    func preferenceSelectionDataSourceMarkAsFavorite(_ dataObject: TimezoneData) {
        _markAsFavorite(dataObject)
    }

    func preferenceSelectionDataSourceUnfavourite(_ dataObject: TimezoneData) {
        _unfavourite(dataObject)
    }

    func preferenceSelectionDataSourceRefreshTimezoneTable() {
        refreshTimezoneTableView()
    }

    func preferenceSelectionDataSourceRefreshMainTableView() {
        refreshMainTable()
    }

    func preferenceSelectionDataSourceTableViewSelectionDidChange(_ status: Bool) {
        deleteButton.isEnabled = !status
    }

    func preferenceSelectionDataSourceTable(didClick tableColumn: NSTableColumn) {
        if tableColumn.identifier.rawValue == "favouriteTimezone" {
            return
        }

        let result = sortingManager.sort(selectedTimeZones, byColumn: tableColumn.identifier.rawValue, ascending: &arePlacesSortedInAscendingOrder)
        timezoneTableView.setIndicatorImage(result.indicatorImage, in: tableColumn)
        DataStore.shared().setTimezones(result.sorted)
        updateAfterSorting()
    }
}

// MARK: - TimezoneAdditionHost

extension PreferencesViewController: TimezoneAdditionHost {}
