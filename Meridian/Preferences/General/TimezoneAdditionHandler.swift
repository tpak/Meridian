// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLocation
import CoreLoggerKit
import CoreModelKit

protocol TimezoneAdditionHost: AnyObject {
    var searchField: NSSearchField! { get }
    var placeholderLabel: NSTextField! { get }
    var availableTimezoneTableView: NSTableView! { get }
    var timezonePanel: CustomPanel! { get }
    var timezoneTableView: NSTableView! { get }
    var messageLabel: NSTextField! { get }
    var addTimezoneButton: NSButton! { get }
    var progressIndicator: NSProgressIndicator! { get }
    var addButton: NSButton! { get }
    var searchResultsDataSource: SearchDataSource! { get }

    func refreshTimezoneTableView(_ shouldSelectNewlyInsertedTimezone: Bool)
    func refreshMainTable()
}

private enum SpecialTimezoneNames {
    static let anywhereOnEarth = "Anywhere on Earth"
    static let utc = "UTC"
}

private let maxTimezoneCount = 100
private let maxSearchLength = 50
private let searchDebounceInterval: TimeInterval = 0.5
private let searchScrollThreshold = 6

@MainActor
class TimezoneAdditionHandler: NSObject {
    private weak var host: TimezoneAdditionHost?
    private let dataStore: DataStoring

    private var searchTask: Task<Void, Never>?
    private var getTimezoneTask: Task<Void, Never>?
    private var installCleanupTask: Task<Void, Never>?

    private var isActivityInProgress = false {
        didSet {
            guard let host = host else { return }
            if isActivityInProgress {
                host.progressIndicator.startAnimation(nil)
            } else {
                host.progressIndicator.stopAnimation(nil)
            }
            host.availableTimezoneTableView.isEnabled = !isActivityInProgress
            host.addButton.isEnabled = !isActivityInProgress
        }
    }

    init(host: TimezoneAdditionHost, dataStore: DataStoring = DataStore.shared()) {
        self.host = host
        self.dataStore = dataStore
    }

    // MARK: - Search

    @objc func search() {
        guard let host = host else { return }
        let searchString = host.searchField.stringValue

        if searchString.isEmpty {
            searchTask?.cancel()
            resetSearchView()
            return
        }

        searchTask?.cancel()

        if host.availableTimezoneTableView.isHidden {
            host.availableTimezoneTableView.isHidden = false
        }

        host.placeholderLabel.isHidden = false
        isActivityInProgress = true
        host.placeholderLabel.placeholderString = "Searching for \(searchString)"

        Logger.debug(host.placeholderLabel.placeholderString ?? "")

        searchTask = Task { @MainActor in
            do {
                let placemark = try await NetworkManager.geocodeAddress(searchString)

                guard let location = placemark.location else {
                    findLocalSearchResultsForTimezones()
                    let noResults = host.searchResultsDataSource.timezoneFilteredArray.isEmpty
                    host.placeholderLabel.placeholderString = noResults
                        ? "No results! Try entering the exact name." : UserDefaultKeys.emptyString
                    reloadSearchResults()
                    isActivityInProgress = false
                    return
                }

                let name = placemark.formattedAddress
                let timezoneID = placemark.timeZone?.identifier ?? ""

                let totalPackage: [String: Any] = [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    UserDefaultKeys.timezoneName: name,
                    UserDefaultKeys.customLabel: name,
                    UserDefaultKeys.timezoneID: timezoneID,
                    UserDefaultKeys.placeIdentifier: placemark.isoCountryCode ?? ""
                ]

                let timezoneData = TimezoneData(with: totalPackage)
                host.searchResultsDataSource.setFilteredArrayValue([timezoneData])

                findLocalSearchResultsForTimezones()
                prepareUIForPresentingResults()
            } catch {
                findLocalSearchResultsForTimezones()
                if host.searchResultsDataSource.timezoneFilteredArray.isEmpty {
                    presentError(error.localizedDescription)
                    return
                }
                prepareUIForPresentingResults()
            }
        }
    }

    private func findLocalSearchResultsForTimezones() {
        guard let host = host else { return }
        TimezoneSearchService.searchLocalTimezones(host.searchField.stringValue, in: host.searchResultsDataSource)
    }

    private func presentError(_ errorMessage: String) {
        guard let host = host else { return }
        if errorMessage == PreferencesConstants.offlineErrorMessage {
            host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
        } else {
            host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
        }
        isActivityInProgress = false
    }

    private func prepareUIForPresentingResults() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        isActivityInProgress = false
        reloadSearchResults()
    }

    private func reloadSearchResults() {
        guard let host = host else { return }
        if host.searchResultsDataSource.calculateChangesets() {
            Logger.debug("Reloading Search Results")
            host.availableTimezoneTableView.reloadData()
        }
    }

    private func resetSearchView() {
        searchTask?.cancel()

        guard let host = host else { return }
        isActivityInProgress = false
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
    }

    // MARK: - Timezone Fetching

    private func getTimezone(for latitude: Double, and longitude: Double) {
        guard let host = host else { return }

        if host.placeholderLabel.isHidden {
            host.placeholderLabel.isHidden = false
        }

        host.searchField.placeholderString = "Fetching data might take some time!"
        host.placeholderLabel.placeholderString = "Retrieving timezone data"
        host.availableTimezoneTableView.isHidden = true

        getTimezoneTask?.cancel()
        getTimezoneTask = Task { @MainActor in
            do {
                let location = CLLocation(latitude: latitude, longitude: longitude)
                let geocoder = CLGeocoder()
                let placemarks = try await geocoder.reverseGeocodeLocation(location)

                guard let placemark = placemarks.first,
                      let timezone = placemark.timeZone else {
                    host.placeholderLabel.placeholderString = "No timezone found! Try entering an exact name."
                    host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                                           comment: "Search Field Placeholder")
                    isActivityInProgress = false
                    return
                }

                if host.availableTimezoneTableView.selectedRow >= 0 {
                    installTimezone(timezone, for: placemark)
                }
                updateViewState()
            } catch {
                let nsError = error as NSError
                if nsError.code == NSURLErrorNotConnectedToInternet || nsError.code == NSURLErrorNetworkConnectionLost {
                    host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
                } else {
                    host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
                }

                isActivityInProgress = false
            }
        }
    }

    private func installTimezone(_ timezone: TimeZone, for placemark: CLPlacemark) {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.debug("Data was unexpectedly nil")
            return
        }

        var filteredAddress = "Error"

        if let address = dataObject.formattedAddress {
            filteredAddress = address.filteredName()
        }

        let newTimeZone = [
            UserDefaultKeys.timezoneID: timezone.identifier,
            UserDefaultKeys.timezoneName: filteredAddress,
            UserDefaultKeys.placeIdentifier: dataObject.placeID ?? "",
            "latitude": dataObject.latitude ?? 0.0,
            "longitude": dataObject.longitude ?? 0.0,
            "nextUpdate": UserDefaultKeys.emptyString,
            UserDefaultKeys.customLabel: filteredAddress
        ] as [String: Any]

        let timezoneObject = TimezoneData(with: newTimeZone)

        let operationsObject = TimezoneDataOperations(with: timezoneObject, store: dataStore)
        operationsObject.saveObject()

        Logger.debug("Filtered Address: PlaceName=\(filteredAddress), Timezone=\(timezone.identifier)")
    }

    private func updateViewState() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        reloadSearchResults()
        host.refreshTimezoneTableView(true)
        host.refreshMainTable()
        host.timezonePanel.close()
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")
        host.availableTimezoneTableView.isHidden = false
        isActivityInProgress = false
    }

    private func showMessage() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
        isActivityInProgress = false
        host.searchResultsDataSource.cleanupFilterArray()
        reloadSearchResults()
    }

    // MARK: - Add to Favorites

    func addToFavorites() {
        guard let host = host else { return }
        isActivityInProgress = true

        if host.availableTimezoneTableView.selectedRow == -1 {
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.noTimezoneSelectedErrorMessage)
            isActivityInProgress = false
            return
        }

        let selectedTimeZones = dataStore.timezones()
        if selectedTimeZones.count >= maxTimezoneCount {
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxTimezonesErrorMessage)
            isActivityInProgress = false
            return
        }

        if host.searchField.stringValue.isEmpty {
            addTimezoneIfSearchStringIsEmpty()
        } else {
            addTimezoneIfSearchStringIsNotEmpty()
        }
    }

    private func addTimezoneIfSearchStringIsEmpty() {
        guard let host = host else { return }
        let currentRowType = host.searchResultsDataSource.placeForRow(host.availableTimezoneTableView.selectedRow)

        switch currentRowType {
        case .timezone:
            cleanupAfterInstallingTimezone()
        default:
            return
        }
    }

    private func addTimezoneIfSearchStringIsNotEmpty() {
        guard let host = host else { return }
        let currentRowType = host.searchResultsDataSource.placeForRow(host.availableTimezoneTableView.selectedRow)

        switch currentRowType {
        case .timezone:
            cleanupAfterInstallingTimezone()
            return
        case .city:
            cleanupAfterInstallingCity()
        }
    }

    private func cleanupAfterInstallingCity() {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.debug("Data was unexpectedly nil")
            return
        }

        if host.messageLabel.stringValue.isEmpty {
            host.searchField.stringValue = UserDefaultKeys.emptyString

            // If the TimezoneData already has a timezoneID from CLGeocoder, install directly
            if let timezoneID = dataObject.timezoneID, !timezoneID.isEmpty {
                let filteredAddress = (dataObject.formattedAddress ?? "Error").filteredName()

                let newTimeZone = [
                    UserDefaultKeys.timezoneID: timezoneID,
                    UserDefaultKeys.timezoneName: filteredAddress,
                    UserDefaultKeys.placeIdentifier: dataObject.placeID ?? "",
                    "latitude": dataObject.latitude ?? 0.0,
                    "longitude": dataObject.longitude ?? 0.0,
                    "nextUpdate": UserDefaultKeys.emptyString,
                    UserDefaultKeys.customLabel: filteredAddress
                ] as [String: Any]

                let timezoneObject = TimezoneData(with: newTimeZone)
                let operationsObject = TimezoneDataOperations(with: timezoneObject, store: dataStore)
                operationsObject.saveObject()

                Logger.debug("Filtered Address: PlaceName=\(filteredAddress), Timezone=\(timezoneID)")
                updateViewState()
            } else {
                // Fall back to reverse geocoding if no timezone ID
                guard let latitude = dataObject.latitude, let longitude = dataObject.longitude else {
                    Logger.debug("Data was unexpectedly nil")
                    return
                }
                getTimezone(for: latitude, and: longitude)
            }
        }
    }

    private func cleanupAfterInstallingTimezone() {
        guard let host = host else { return }
        let data = TimezoneData()
        data.setLabel(UserDefaultKeys.emptyString)

        let currentSelection = host.searchResultsDataSource.retrieveSelectedTimezone(host.availableTimezoneTableView.selectedRow)

        let metaInfo = metadata(for: currentSelection)
        data.timezoneID = metaInfo.0.name
        data.formattedAddress = metaInfo.1.formattedName
        data.selectionType = .timezone
        data.isSystemTimezone = metaInfo.0.name == NSTimeZone.system.identifier

        // Geocode coordinates before saving so sunrise/sunset works immediately
        let timezoneID = metaInfo.0.name
        let store = self.dataStore
        installCleanupTask?.cancel()
        installCleanupTask = Task { @MainActor in
            let components = timezoneID.split(separator: "/")
            if let cityComponent = components.last {
                let cityName = cityComponent.replacingOccurrences(of: "_", with: " ")
                guard let placemark = try? await NetworkManager.geocodeAddress(cityName),
                      let location = placemark.location else {
                    Logger.debug("Coordinate backfill skipped for \(cityName)")
                    let operationObject = TimezoneDataOperations(with: data, store: store)
                    operationObject.saveObject()
                    host.searchResultsDataSource.cleanupFilterArray()
                    host.searchResultsDataSource.timezoneFilteredArray = []
                    host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
                    host.searchField.stringValue = UserDefaultKeys.emptyString
                    self.reloadSearchResults()
                    host.refreshTimezoneTableView(true)
                    host.refreshMainTable()
                    host.timezonePanel.close()
                    host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                                           comment: "Search Field Placeholder")
                    host.availableTimezoneTableView.isHidden = false
                    self.isActivityInProgress = false
                    return
                }
                data.latitude = location.coordinate.latitude
                data.longitude = location.coordinate.longitude
            }

            let operationObject = TimezoneDataOperations(with: data, store: store)
            operationObject.saveObject()

            host.searchResultsDataSource.cleanupFilterArray()
            host.searchResultsDataSource.timezoneFilteredArray = []
            host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
            host.searchField.stringValue = UserDefaultKeys.emptyString

            self.reloadSearchResults()
            host.refreshTimezoneTableView(true)
            host.refreshMainTable()

            host.timezonePanel.close()
            host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                                   comment: "Search Field Placeholder")
            host.availableTimezoneTableView.isHidden = false
            self.isActivityInProgress = false
        }
    }

}

// MARK: - Close Panel, Filter & Selection

extension TimezoneAdditionHandler {
    func closePanel() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        host.searchResultsDataSource.timezoneFilteredArray = []
        host.searchField.stringValue = UserDefaultKeys.emptyString
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")

        reloadSearchResults()

        host.timezonePanel.close()
        isActivityInProgress = false
        host.addTimezoneButton.state = .off

        host.availableTimezoneTableView.isHidden = false
    }

    func filterArray() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()

        if host.searchField.stringValue.count > maxSearchLength {
            isActivityInProgress = false
            reloadSearchResults()
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxCharactersAllowed)
            return
        }

        if host.searchField.stringValue.isEmpty == false {
            searchTask?.cancel()
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            perform(#selector(search), with: nil, afterDelay: searchDebounceInterval)
        } else {
            resetSearchView()
        }

        reloadSearchResults()
    }

    func selectNewlyInsertedTimezone() {
        guard let host = host else { return }
        if host.timezoneTableView.numberOfRows > searchScrollThreshold {
            host.timezoneTableView.scrollRowToVisible(host.timezoneTableView.numberOfRows - 1)
        }

        let indexSet = IndexSet(integer: IndexSet.Element(host.timezoneTableView.numberOfRows - 1))
        host.timezoneTableView.selectRowIndexes(indexSet, byExtendingSelection: false)
    }

    private func metadata(for selection: TimezoneMetadata) -> (NSTimeZone, TimezoneMetadata) {
        if selection.formattedName == SpecialTimezoneNames.anywhereOnEarth {
            return (NSTimeZone(name: "GMT-1200") ?? NSTimeZone.default as NSTimeZone, selection)
        } else if selection.formattedName == SpecialTimezoneNames.utc {
            return (NSTimeZone(name: "GMT") ?? NSTimeZone.default as NSTimeZone, selection)
        } else {
            return (selection.timezone, selection)
        }
    }
}
